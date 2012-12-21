library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

--library ana_va_00_a;
--use ana_v1_00_a.anaPkg.all;
--use work.hwt_aes_yyang_pkg.all;
library ana_v1_00_a;
use ana_v1_00_a.anaPkg.all;

entity control is
  port(
    clk:                  in std_logic;
    rst:                  in std_logic;
    keyValid:             in std_logic;
    startExp:             out std_logic;
    permitEnc:            out std_logic;
    
    keyWord:              out std_logic_vector(31 downto 0);
    globalLocalAddr:      out std_logic_vector(5 downto 0);
    mode:                 out std_logic_vector(1 downto 0)
  );
end control;

architecture rtl of control is
  
  signal cipherKey:       CIPHERKEY256_ARRAY;
  signal cipherKey_p:     CIPHERKEY256_ARRAY;
  signal cipherKey_n:     CIPHERKEY256_ARRAY;
  signal mode_p:          std_logic_vector(1 downto 0);
  signal mode_n:          std_logic_vector(1 downto 0);
  signal startExp_p:      std_logic;
  signal startExp_n:      std_logic;
  signal startEnc_p:      std_logic;
  signal startEnc_n:      std_logic;
  signal keyWord_p:       std_logic_vector(31 downto 0);
  signal keyWord_n:       std_logic_vector(31 downto 0);
  signal counter_p:       integer range 0 to 8;
  signal counter_n:       integer range 0 to 8;
  constant ZEROKEY:       CIPHERKEY256_ARRAY:=(others=>X"00000000");
  type stateType is(
    waitKey,
    loadKey,
    expanKey,
    waitKeyValid,
    startEnc,
    encPkt
  );
  signal state_p:         stateType;
  signal state_n:         stateType;
  
  begin
    
    keyWord         <=keyWord_p;
    mode            <=mode_p;
    permitEnc       <=startEnc_p;
    startExp        <=startExp_p;
    globalLocalAddr <="0001"&"00";
    
    process(rst, clk)
      begin
        if rst='1'then
          state_p         <=waitKey;
          mode_p          <=mode256;
          startExp_p      <='0';
          startEnc_p      <='0';
          keyWord_p       <=X"FFFFFFFF";
          --cipherKey_p     <=ZEROKEY;
			   cipherKey_p(0) <=X"03020100";
            cipherKey_p(1) <=X"07060504";
            cipherKey_p(2) <=X"0b0a0908";
            cipherKey_p(3) <=X"0f0e0d0c";
            cipherKey_p(4) <=X"13121110";
            cipherKey_p(5) <=X"17161514";
            cipherKey_p(6) <=X"1b1a1918";
            cipherKey_p(7) <=X"1f1e1d1c";
          counter_p       <=0;
        elsif rising_edge(clk)then
          state_p         <=state_n;
          mode_p          <=mode_n;
          startExp_p      <=startExp_n;
          startEnc_p      <=startEnc_n;
          keyWord_p       <=keyWord_n;
          cipherKey_p     <=cipherKey_n;
          counter_p       <=counter_n;
        end if;
      end process;
      
      
      
      process(state_p, counter_p, mode_p, startExp_p, startEnc_p, keyWord_p, cipherKey_p, keyValid)
        begin
          
          state_n         <=state_p;
          counter_n       <=counter_p;
          mode_n          <=mode_p;
          startExp_n      <=startExp_p;
          startEnc_n      <=startEnc_p;
          keyWord_n       <=keyWord_p;
          cipherKey_n     <=cipherKey_p;
          
          case state_p is
          when waitKey=>
            
--            -- 128 bit key
--            cipherKey_n(0) <=X"16157e2b";
--            cipherKey_n(1) <=X"a6d2ae28";
--            cipherKey_n(2) <=X"8815f7ab";
--            cipherKey_n(3) <=X"3c4fcf09";
--            state_n        <=loadKey;
--            counter_n      <=0;
--            mode_n         <=mode128;
--            startExp_n     <='0';
--            startEnc_n     <='0';
            
--            -- 128 bit key
--            cipherKey_n(0) <=X"03020100";
--            cipherKey_n(1) <=X"07060504";
--            cipherKey_n(2) <=X"0b0a0908";
--            cipherKey_n(3) <=X"0f0e0d0c";
--            state_n        <=loadKey;
--            counter_n      <=0;
--            mode_n         <=mode128;
--            startExp_n     <='0';
--            startEnc_n     <='0';

--            --192 bit key
--            cipherKey_n(0) <=X"03020100";
--            cipherKey_n(1) <=X"07060504";
--            cipherKey_n(2) <=X"0b0a0908";
--            cipherKey_n(3) <=X"0f0e0d0c";
--            cipherKey_n(4) <=X"13121110";
--            cipherKey_n(5) <=X"17161514";
--            state_n        <=loadKey;
--            counter_n      <=0;
--            mode_n         <=mode192;
--            startExp_n     <='0';
--            startEnc_n     <='0';
            
            --256 bit key:
            cipherKey_n(0) <=X"03020100";
            cipherKey_n(1) <=X"07060504";
            cipherKey_n(2) <=X"0b0a0908";
            cipherKey_n(3) <=X"0f0e0d0c";
            cipherKey_n(4) <=X"13121110";
            cipherKey_n(5) <=X"17161514";
            cipherKey_n(6) <=X"1b1a1918";
            cipherKey_n(7) <=X"1f1e1d1c";
            state_n        <=loadKey;
            counter_n      <=0;
            startExp_n     <='0';
            startEnc_n     <='0';
            mode_n         <=mode256;

          when loadKey=>
            state_n        <=expanKey;
            keyWord_n      <=cipherKey_p(counter_p);
            counter_n      <=1;
            startExp_n     <='1';
          when expanKey=>
            case counter_p is
            when 8=>
              state_n      <=waitKeyValid;
              startExp_n   <='0';
            when others=>
              counter_n    <=counter_p+1;
              keyWord_n    <=cipherKey_p(counter_p);
            end case;
          when waitKeyValid=>
            if keyValid='1'then
              state_n      <=startEnc;
              startEnc_n   <='1';
            else
              state_n      <=state_p;
            end if;
          when startEnc=>
            state_n        <=encPkt;
          when encPkt=>
            startEnc_n     <='0';
          end case;
        end process;
                      

 end rtl;     
      
      
      
      
          
