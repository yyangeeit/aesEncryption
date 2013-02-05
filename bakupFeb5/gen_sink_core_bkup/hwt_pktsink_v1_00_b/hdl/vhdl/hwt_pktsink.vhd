library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library proc_common_v3_00_a;
use proc_common_v3_00_a.proc_common_pkg.all;

library reconos_v3_00_a;
use reconos_v3_00_a.reconos_pkg.all;

library ana_v1_00_a;
use ana_v1_00_a.anaPkg.all;

entity hwt_pktsink is

	port (
		-- OSIF FSL
		OSFSL_Clk       : in  std_logic;                 -- Synchronous clock
		OSFSL_Rst       : in  std_logic;
		OSFSL_S_Clk     : out std_logic;                 -- Slave asynchronous clock
		OSFSL_S_Read    : out std_logic;                 -- Read signal, requiring next available input to be read
		OSFSL_S_Data    : in  std_logic_vector(0 to 31); -- Input data
		OSFSL_S_Control : in  std_logic;                 -- Control Bit, indicating the input data are control word
		OSFSL_S_Exists  : in  std_logic;                 -- Data Exist Bit, indicating data exist in the input FSL bus
		OSFSL_M_Clk     : out std_logic;                 -- Master asynchronous clock
		OSFSL_M_Write   : out std_logic;                 -- Write signal, enabling writing to output FSL bus
		OSFSL_M_Data    : out std_logic_vector(0 to 31); -- Output data
		OSFSL_M_Control : out std_logic;                 -- Control Bit, indicating the output data are contol word
		OSFSL_M_Full    : in  std_logic;                 -- Full Bit, indicating output FSL bus is full
		
		-- FIFO Interface
		FIFO32_S_Data   : in std_logic_vector(31 downto 0);
		FIFO32_M_Data   : out std_logic_vector(31 downto 0);
		FIFO32_S_Fill   : in std_logic_vector(15 downto 0);
		FIFO32_M_Rem    : in std_logic_vector(15 downto 0);
		FIFO32_S_Rd     : out std_logic;
		FIFO32_M_Wr     : out std_logic;
		
		-- HWT reset
		rst             : in std_logic;

		switch_data_rdy	: in  std_logic;
		switch_data		   : in  std_logic_vector(dataWidth downto 0);
		thread_read_rdy	: out std_logic;
		switch_read_rdy	: in  std_logic;
		thread_data		   : out std_logic_vector(dataWidth downto 0);
		thread_data_rdy : out std_logic	

	);

end hwt_pktsink;

architecture implementation of hwt_pktsink is
  
  signal switch_read_rdy_i:   std_logic;
  signal thread_data_i:		     std_logic_vector(8 downto 0);
  signal thread_data_rdy_i:	  std_logic;
  
	constant MBOX_RECV         : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000000";
	constant MBOX_SEND         : std_logic_vector(C_FSL_WIDTH-1 downto 0) := x"00000001";
	signal ignore		            : std_logic_vector(C_FSL_WIDTH-1 downto 0);
	signal data                : std_logic_vector(31 downto 0);
	signal i_osif              : i_osif_t;
	signal o_osif              : o_osif_t;
	signal i_memif             : i_memif_t;
	signal o_memif             : o_memif_t;
	signal i_ram               : i_ram_t;
	signal o_ram               : o_ram_t;
  signal startRcv            : std_logic;
  signal allPktsRcvd         : std_logic;
  signal clkCounter           : std_logic_vector(63 downto 0);
  signal pktNumCounter        :std_logic_vector(31 downto 0);
	signal pktDecoder_sof	                 : std_logic;
	signal pktDecoder_eof	                 : std_logic;
	signal pktDecoder_data	                : std_logic_vector(7 downto 0);
	signal pktDecoder_src_rdy	             : std_logic;
	signal pktDecoder_dst_rdy	             : std_logic;
	signal pktDecoder_direction            : std_logic;
	signal pktDecoder_priority             : std_logic_vector(1 downto 0);
	signal pktDecoder_latency_critical     : std_logic;
	signal pktDecoder_srcIdp               : std_logic_vector(31 downto 0);
	signal pktDecoder_dstIdp               : std_logic_vector(31 downto 0);
	signal pktDecoder_global_addr          : std_logic_vector(3 downto 0);
	signal pktDecoder_local_addr           : std_logic_vector(1 downto 0);


  type stateType is(
    waitCommand,
    getPktNumber,
    sendAck,
    rcvPkt,
    sendFeedback1,
    sendFeedback2,
    state_thread_exit
  );
  signal pktNumber:         std_logic_vector(31 downto 0);
  signal state:             stateType; 
   
  component pktSinkCore is
	port (
	  clk                :in std_logic;
	  rst                :in std_logic;
	  startRcv           :in std_logic;
	  pktNumber          :in std_logic_vector(31 downto 0);
	  pktDecoder_sof     :in std_logic;
	  pktDecoder_eof     :in std_logic;
	  pktDecoder_data    :in std_logic_vector(7 downto 0);
	  pktDecoder_src_rdy :in std_logic;
	  pktDecoder_dst_rdy :out std_logic;
	  clkCounter         :out std_logic_vector(63 downto 0);
	  pktNumCounter      :out std_logic_vector(31 downto 0);
	  allPktsRcvd        :out std_logic
	);	
  end component;
  
begin

  switch_read_rdy_i<=switch_read_rdy;
  thread_data<="100010001";
  thread_data_rdy<='0';

	decoder_inst : packetDecoder
	port map (
		clk 	                 => i_osif.clk,
		reset 	               => rst,

		-- Signals from the switch
		switch_data_rdy		     => switch_data_rdy,
		switch_data		         => switch_data,
		thread_read_rdy		     => thread_read_rdy,

		-- Decoded values of the packet
		noc_rx_sof		          => pktDecoder_sof,		         -- Indicates the start of a new packet
		noc_rx_eof		          => pktDecoder_eof,		         -- Indicates the end of the packet
		noc_rx_data		         => pktDecoder_data,		        -- The current data byte
		noc_rx_src_rdy		      => pktDecoder_src_rdy, 	     -- '1' if the data are valid, '0' else
		noc_rx_direction	     => pktDecoder_direction, 		        -- '1' for egress, '0' for ingress
		noc_rx_priority		     => pktDecoder_priority,		          -- The priority of the packet
		noc_rx_latencyCritical=> pktDecoder_latency_critical,		  -- '1' if this packet is latency critical
		noc_rx_srcIdp		       => pktDecoder_srcIdp,		            -- The source IDP
		noc_rx_dstIdp		       => pktDecoder_dstIdp,		            -- The destination IDP
		noc_rx_dst_rdy		      => pktDecoder_dst_rdy	       -- Read enable for the functional block
	);
	
	sinkCore_inst: pktSinkCore
	port map(
  	  clk                  =>i_osif.clk,
  	  rst                  =>rst,
  	  startRcv             =>startRcv,
  	  pktNumber            =>pktNumber,
  	  pktDecoder_sof       =>pktDecoder_sof,
  	  pktDecoder_eof       =>pktDecoder_eof,
  	  pktDecoder_data      =>pktDecoder_data,
  	  pktDecoder_src_rdy   =>pktDecoder_src_rdy,
  	  pktDecoder_dst_rdy   =>pktDecoder_dst_rdy,
  	  clkCounter           =>clkCounter,
  	  pktNumCounter        =>pktNumCounter,
  	  allPktsRcvd          =>allPktsRcvd  
	);

	fsl_setup(
		i_osif,
		o_osif,
		OSFSL_Clk,
		OSFSL_Rst,
		OSFSL_S_Data,
		OSFSL_S_Exists,
		OSFSL_M_Full,
		OSFSL_M_Data,
		OSFSL_S_Read,
		OSFSL_M_Write,
		OSFSL_M_Control
	);
		
	memif_setup(
		i_memif,
		o_memif,
		OSFSL_Clk,
		FIFO32_S_Data,
		FIFO32_S_Fill,
		FIFO32_S_Rd,
		FIFO32_M_Data,
		FIFO32_M_Rem,
		FIFO32_M_Wr
	);
	
  reconos_fsm: process(i_osif.clk, rst, o_osif, o_memif, o_ram)is
  variable done:    boolean;
  begin
    if rst='1'then
      osif_reset(o_osif);
      memif_reset(o_memif);
      pktNumber         <=X"00000064";--100 pkts
      state             <=waitCommand;
    elsif rising_edge(i_osif.clk)then
    case state is
      
    when waitCommand=>
      osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
      if done then
        case data is
        when X"00000001"=>
          state<=getPktNumber;
        when others=>
          state<=waitCommand;
        end case;
      end if;
      
    when getPktNumber=>
      osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
      if done then
        if (data=X"FFFFFFFF")then
          state<=state_thread_exit;
        else
          pktNumber<=data;
          state<=sendAck;
        end if;
      end if;
      
    when sendAck=>
      if pktDecoder_src_rdy='1'then
        osif_mbox_put(i_osif, o_osif, MBOX_SEND, pktNumber, ignore, done);
        if done then
          startRcv<='1';
          state<=rcvPkt;
        end if;
      end if;
   
    when rcvPkt=>
      if pktNumCounter=X"00000005" then
        state<=sendFeedback1;
      end if;
      
    when sendFeedback1=>
      osif_mbox_put(i_osif, o_osif, MBOX_SEND, clkCounter(31 downto 0), ignore, done);
      if done then
        state<=sendFeedback2;
      end if;
      
    when sendFeedback2=>
      osif_mbox_put(i_osif, o_osif, MBOX_SEND, clkCounter(63 downto 32), ignore, done);
      if done then
        state<=waitCommand;
      end if;
      
    when others=>
      osif_thread_exit(i_osif,o_osif);      
    end case;
  
  end if;
end process;

end architecture;
