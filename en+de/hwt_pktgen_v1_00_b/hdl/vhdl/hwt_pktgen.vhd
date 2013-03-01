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

entity hwt_pktgen is

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

end hwt_pktgen;

architecture implementation of hwt_pktgen is
  
  signal switch_data_rdy_i    :std_logic;
  signal switch_data_i        :std_logic_vector(dataWidth downto 0);
  signal thread_read_rdy_i    :std_logic;
   
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
	
--	signal startGen            : std_logic;
--	signal allPktsSent         : std_logic;	
	signal pktEncoder_sof	                : std_logic;
	signal pktEncoder_eof	                : std_logic;
	signal pktEncoder_data	               : std_logic_vector(7 downto 0);
	signal pktEncoder_src_rdy	            : std_logic;
  signal pktEncoder_global_addr         : std_logic_vector(3 downto 0);
	signal pktEncoder_local_addr          : std_logic_vector(1 downto 0);
	signal pktEncoder_direction           : std_logic;
	signal pktEncoder_priority            : std_logic_vector(1 downto 0);
	signal pktEncoder_latency_critical    : std_logic;
	signal pktEncoder_srcIdp              : std_logic_vector(31 downto 0);
	signal pktEncoder_dstIdp              : std_logic_vector(31 downto 0);
	signal pktEncoder_dst_rdy	            : std_logic;	

  type stateType is(
    waitStart,
    getPktRoute,
    getPktNumFsl,
    getPktLenFsl,
    sendAckRcvd,
    sendPkts,
    sendAckDone,
    finish,
    threadExit
  );
--  type stateType is(
--    waitStart,
--    sendPkts,
--    sendAckDone,
--    finish,
--    state_thread_exit
--  );
  signal state:       stateType;
	signal pktVector           : std_logic_vector(10 downto 0);
  signal pktRoute             :std_logic_vector(5 downto 0);                   --sw: 5 => hw:000101 =>h2s<pkSink>;  --sw: 1=> hw: 000001 =>hwt_aes.	   
  constant pktHead            :std_logic_vector(10 downto 0) :="10000000011";  --bit 10: sof, bit 9: eof, bit 8~1: data, bit 0: pktEncoder_src_rdy.
  constant pktMid             :std_logic_vector(10 downto 0) :="00000000101";
  constant pktEnd             :std_logic_vector(10 downto 0) :="01000001001";
  constant pktNotReady        :std_logic_vector(10 downto 0) :="00111111110"; 
  
  constant pktNum             :std_logic_vector(31 downto 0) :=X"000007D0";   --2000 pkts
  constant pktLen             :std_logic_vector(31 downto 0) :=X"000005DC";   --length: 1500 Bytes/pkt    

  signal pktNumFsl:            std_logic_vector(31 downto 0);
  signal pktLenFsl:            std_logic_vector(31 downto 0);

  signal byteCounter:         std_logic_vector(31 downto 0);                        --count how many bytes of this packet have been sent
  signal pktCounter:          std_logic_vector(31 downto 0);                        --count how many packets have been sent

begin

  switch_data_rdy_i<=switch_data_rdy;
  switch_data_i<=switch_data;
  thread_read_rdy<='0';
	
	pktEncoder_sof               <=pktVector(10);
	pktEncoder_eof               <=pktVector(9);
	pktEncoder_data              <=pktVector(8 downto 1);
	pktEncoder_src_rdy           <=pktVector(0);
	pktEncoder_global_addr       <=pktRoute(5 downto 2);
	pktEncoder_local_addr        <=pktRoute(1 downto 0);                         --"0000"&"01"=>send to hwt_aes
--	pktEncoder_global_addr       <="0000";
--	pktEncoder_local_addr        <="01";                         --"0000"&"01"=>send to hwt_aes
	pktEncoder_direction         <='0';
	pktEncoder_priority          <="01";
	pktEncoder_latency_critical  <='1';
	pktEncoder_srcIdp            <=x"aabbccaa";
	pktEncoder_dstIdp            <=x"ddeeffdd";
	
	encoder_inst : packetEncoder
	port map(
		clk 				              => i_osif.clk,					
		reset 				            => rst,
				
		-- Signals to the switch
		switch_read_rdy  		   => switch_read_rdy, 		
		thread_data  			      => thread_data,		
		thread_data_rdy 		    => thread_data_rdy,
		
		-- Encoded values of the packet
		noc_tx_sof  			       => pktEncoder_sof, 		
		noc_tx_eof  			       => pktEncoder_eof,
		noc_tx_data	 		       => pktEncoder_data,		
		noc_tx_src_rdy 	 		   => pktEncoder_src_rdy,		
		noc_tx_globalAddress  => pktEncoder_global_addr,         --"0000",--(others => '0'), --6 bits--(0:send it to hw/sw)		
		noc_tx_localAddress  	=> pktEncoder_local_addr,          --"01",-- (others  => '0'), --2 bits		
		noc_tx_direction 	 	  => pktEncoder_direction,		
		noc_tx_priority 	 	   => pktEncoder_priority,		
		noc_tx_latencyCritical=> pktEncoder_latency_critical,	
		noc_tx_srcIdp 			     => pktEncoder_srcIdp,	
		noc_tx_dstIdp 			     => pktEncoder_dstIdp,
		noc_tx_dst_rdy	 		    => pktEncoder_dst_rdy
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
      state       <=waitStart;
      pktVector   <=pktNotReady;
      byteCounter <=(others=>'0');
      pktCounter  <=(others=>'0');
      pktNumFsl   <=X"000007D0";    --pkt:2000 pkts
      pktLenFsl   <=X"000003E8";    --len:1000 B
      pktRoute    <="000001";
    elsif rising_edge(i_osif.clk)then
      case state is
        
      when waitStart=>
        osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
        if done then
          if (data=X"FFFFFFFF")then
            state       <=threadExit;
          elsif data=X"00000001"then
		        state	<=getPktRoute;
          end if;
        end if;
        
      when getPktRoute=>
        osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
        if done then
          if (data=X"FFFFFFFF")then
            state       <=threadExit;
          else
            pktRoute    <=data(5 downto 0);
		        state	      <=getPktNumFsl;
          end if;
        end if;
        
      when getPktNumFsl=>
        osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
        if done then
          if (data=X"FFFFFFFF")then
            state       <=threadExit;
          else
            pktNumFsl   <=data;
		        state	      <=getPktLenFsl;
          end if;
        end if;
               
      when getPktLenFsl=>
        osif_mbox_get(i_osif, o_osif, MBOX_RECV, data, done);
        if done then
          if (data=X"FFFFFFFF")then
            state       <=threadExit;
          else
            pktLenFsl   <=data;
		        state	      <=sendAckRcvd;
          end if;
        end if;
        
      when sendAckRcvd=>
  	    osif_mbox_put(i_osif, o_osif, MBOX_SEND, pktLenFsl, ignore, done);
  	    if done then
  	     pktVector   <=pktHead;
  		    state       <=sendPkts;
  	    end if;             
        
      when sendPkts=>
        if pktEncoder_dst_rdy='1' then
          if pktCounter=pktNumFsl then
            pktVector       <=pktEnd;
            state           <=sendAckDone;
          else
            if byteCounter=pktLenFsl-1 then
              pktVector     <=pktEnd;
              byteCounter   <=byteCounter+1;
            elsif byteCounter=pktLenFsl then
              pktVector     <=pktHead;
              byteCounter   <=(others=>'0');
              pktCounter    <=pktCounter+1;
            else
              pktVector     <=pktMid;
              byteCounter   <=byteCounter+1;
            end if;
          end if;
        else
          pktCounter          <=pktCounter;
          byteCounter         <=byteCounter;
        end if;
   
      when sendAckDone=>
  	    osif_mbox_put(i_osif, o_osif, MBOX_SEND, pktCounter, ignore, done);
  	    if done then
  		    state<=finish;
  	    end if;
	    
	    when finish=>
	      pktVector      <=pktNotReady;
        
      when others=>
        osif_thread_exit(i_osif,o_osif);
      end case;
      
    end if;
  end process;

end architecture;	

--  reconos_fsm: process(i_osif.clk, rst, o_osif, o_memif, o_ram)is
--  variable done:    boolean;
--  begin
--    if rst='1'then
--      osif_reset(o_osif);
--      memif_reset(o_memif);
--      state       <=waitStart;
--      pktVector   <=pktNotReady;
--      byteCounter <=(others=>'0');
--      pktCounter  <=(others=>'0');
--      pktNumFsl   <=X"000007D0";    --pkt:2000 pkts
--      pktLenFsl   <=X"000003E8";    --len:1000 B
--    elsif rising_edge(i_osif.clk)then
--      case state is
--        
--      when waitStart=>
--        pktVector   <=pktHead;  
--        state       <=sendPkts;
--        
--      when sendPkts=>
--        if pktEncoder_dst_rdy='1' then
--          case pktCounter is
--          when pktNum=>                    --send 100 pkts
--            pktVector <=pktEnd;
--            state     <=sendAckDone;
--          when others=>
--            case byteCounter is
--            when pktLen-1=>
--              pktVector       <=pktEnd;
--              byteCounter     <=byteCounter+1;
--            when pktLen=>
--              pktVector       <=pktHead;
--              byteCounter     <=(others=>'0');
--              pktCounter      <=pktCounter+1;
--            when others=>
--              pktVector       <=pktMid;
--              byteCounter     <=byteCounter+1;
--            end case;
--          end case;
--        else
--          pktCounter          <=pktCounter;
--          byteCounter         <=byteCounter;
--        end if;
--   
--      when sendAckDone=>
--  	    osif_mbox_put(i_osif, o_osif, MBOX_SEND, pktCounter, ignore, done);
--  	    if done then
--  		    state<=finish;
--  	    end if;
--	    
--	    when finish=>
--	      pktVector      <=pktNotReady;
--        
--      when others=>
--        osif_thread_exit(i_osif,o_osif);
--      end case;
--      
--    end if;
--  end process;
--
--end architecture;
