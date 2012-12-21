library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

--use work.hwt_aes_yyang_pkg.all;
library ana_v1_00_a;
use ana_v1_00_a.anaPkg.all;

entity keyExpansion is
  port(
    clk                     :in std_logic;
    rst                     :in std_logic;
    en                      :in std_logic;
    mode                    :in std_logic_vector(1 downto 0);
    startExpansion          :in std_logic;
    newWord                 :in std_logic_vector(31 downto 0);
    addrA                   :in std_logic_vector(3 downto 0);
    addrB                   :in std_logic_vector(3 downto 0);
    addrC                   :in std_logic_vector(3 downto 0);
    --addrD                   :in std_logic_vector(3 downto 0);
    keyA                    :out DATA_ARRAY;
    keyB                    :out DATA_ARRAY;
    keyC                    :out DATA_ARRAY;
    --keyD                    :out DATA_ARRAY;
    keyValid                :out std_logic
  );
end keyExpansion;

architecture keyExpansion of keyExpansion is
  type stateType is(
    waitKey,
    prepKey,
    calcKey,
    restKey,
    valiKey
  );
  type sBoxArray  is array(0 to 3)  of std_logic_vector (7 downto 0);
  TYPE RCON_ARRAY is array(0 to 9)  of std_logic_vector (31 downto 0);
  constant RCON: RCON_ARRAY:=(
		0 => X"00000001", 
		1 => X"00000002", 
		2 => X"00000004", 
		3 => X"00000008", 
		4 => X"00000010", 
		5 => X"00000020", 
		6 => X"00000040", 
		7 => X"00000080", 
		8 => X"0000001B", 
		9 => X"00000036"
	);
  signal key:               KEY256_ARRAY;
  signal key_n:             KEY256_ARRAY;
  signal key_p:             KEY256_ARRAY;
  
  signal wordAddr_n:        integer range 0 to 60; 
  signal wordAddr_p:        integer range 0 to 60;
  
  signal mode_p:            std_logic_vector(1 downto 0);  
  signal mode_n:            std_logic_vector(1 downto 0);
  
  signal state_p:           stateType;
  signal state_n:           stateType;
  
  signal counter_p:         integer range 0 to 59;
  signal counter_n:         integer range 0 to 59;
  
  signal step_p:            integer range 0 to 7;
  signal step_n:            integer range 0 to 7;
  
  signal addr_p:            sBoxArray;
  signal addr_n:            sBoxArray;
  signal sByte:             sBoxArray;
  
  BEGIN
    key<=key_p;
    
    sBox0:  sBox
    port map(
      clk   =>clk,
      rst   =>rst,
      addr  =>addr_p(0),
      sByte =>sByte(0)
    );
    sBox1:  sBox
    port map(
      clk   =>clk,
      rst   =>rst,
      addr  =>addr_p(1),
      sByte =>sByte(1)
    );
    sBox2:  sBox
    port map(
      clk   =>clk,
      rst   =>rst,
      addr  =>addr_p(2),
      sByte =>sByte(2)
    );
    sBox3:  sBox
    port map(
      clk   =>clk,
      rst   =>rst,
      addr  =>addr_p(3),
      sByte =>sByte(3)
    );
    
    process(rst,clk)
    begin
      if(rst='1')then
         wordAddr_p         <=0;
         state_p            <=waitKey;
         counter_p          <=0;
         step_p             <=0;
         mode_p             <=mode128;
         key_p              <=(others=>X"FFFFFFFF");
         addr_p             <=(others=>X"00");
      elsif rising_edge(clk)then
         wordAddr_p         <=wordAddr_n;
         state_p            <=state_n;
         counter_p          <=counter_n;
         step_p             <=step_n;
         mode_p             <=mode_n;
         key_p              <=key_n;
         addr_p             <=addr_n;
      end if;
    end process;
     
    process(state_p, counter_p, step_p, mode_p, newWord, mode, startExpansion, key, addr_p, wordaddr_p, sByte, key_p)
      variable tmp: std_logic_vector(31 downto 0);
      begin
        key_n               <=key_p;
        state_n             <=state_p;
        mode_n              <=mode_p;
        counter_n           <=counter_p;
        step_n              <=step_p;
        wordAddr_n          <=wordAddr_p;
        addr_n              <=addr_p;
        
        case state_p is
          
        when waitKey=>
          if(startExpansion='1')then
            state_n         <=prepKey;
            counter_n       <=0;
            step_n          <=1;
            mode_n          <=mode;
            key_n(0)        <=newWord;        
            wordAddr_n      <=1;
          else
            state_n         <=state_p;
          end if;
          
          
        when prepKey=>
          case mode_p is           
          when mode128=>
            if(step_p=3)then
              addr_n(0)     <=newWord(15 downto 8);
              addr_n(1)     <=newWord(23 downto 16);
              addr_n(2)     <=newWord(31 downto 24);
              addr_n(3)     <=newWord(7 downto 0);
              state_n       <=restKey;
              counter_n     <=1;
              step_n        <=0;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=4;
            else
              step_n        <=step_p+1;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=wordAddr_p+1;
            end if;
            
          when mode192=>
            if(step_p=5)then
              addr_n(0)     <=newWord(15 downto 8);
              addr_n(1)     <=newWord(23 downto 16);
              addr_n(2)     <=newWord(31 downto 24);
              addr_n(3)     <=newWord(7 downto 0);
              state_n       <=restKey;
              counter_n     <=1;
              step_n        <=0;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=6;
              mode_n        <=mode_p;
            else
              step_n        <=step_p+1;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=wordAddr_p+1;
            end if;
            
          when others=>
            if(step_p=7)then
              addr_n(0)     <=newWord(15 downto 8);
              addr_n(1)     <=newWord(23 downto 16);
              addr_n(2)     <=newWord(31 downto 24);
              addr_n(3)     <=newWord(7 downto 0);
              state_n       <=restKey;
              counter_n     <=1;
              step_n        <=0;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=8;
            else
              step_n        <=step_p+1;
              key_n(wordAddr_p)<=newWord;
              wordAddr_n    <=wordAddr_p+1;
            end if;
          end case;
          
        when calcKey=>
          case mode_p is
            
          when mode128=>
            case wordAddr_p is
            when 44=>
              state_n       <=valiKey;
              counter_n     <=0;
              step_n        <=0;
              wordAddr_n    <=0;
            when others=>
              if(step_p=0)then
                step_n        <=step_p+1;
                key_n(wordAddr_p)<=RCON(counter_p-1) XOR (sByte(3)&sByte(2)&sByte(1)&sByte(0)) XOR key_p(wordAddr_p-4);
                wordAddr_n    <=wordAddr_p+1;
              elsif ((step_p=1)OR(step_p=2))then
                step_n        <=step_p+1;
                key_n(wordAddr_p)<=key_p(wordAddr_p-1) XOR key(wordAddr_p-4);
                wordAddr_n    <=wordAddr_p+1;
              else
                counter_n     <=counter_p+1;
                step_n        <=0;
                tmp           :=key_p(wordAddr_p-1) XOR key(wordAddr_p-4);
                key_n(wordAddr_p)<=tmp;
                wordAddr_n    <=wordAddr_p+1;
                addr_n(0)     <=tmp(15 downto 8);
                addr_n(1)     <=tmp(23 downto 16);
                addr_n(2)     <=tmp(31 downto 24);
                addr_n(3)     <=tmp(7 downto 0);
                state_n       <=restKey;
              end if;
            end case;
            
          when mode192=>
            case wordAddr_p is
            when 52=>
              state_n       <=valiKey;
              counter_n     <=0;
              step_n        <=0;
              wordAddr_n    <=0;
            when others=>
              if(step_p=0)then
                step_n        <=step_p+1;
                key_n(wordAddr_p)        <=RCON(counter_p-1) XOR (sByte(3)&sByte(2)&sByte(1)&sByte(0)) XOR key(wordAddr_p-6);
                wordAddr_n    <=wordAddr_p+1;
              elsif ((step_p=1)OR(step_p=2)OR(step_p=3)OR(step_p=4))then
                step_n        <=step_p+1;
                key_n(wordAddr_p)        <=key_p(wordAddr_p-1) XOR key(wordAddr_p-6);
                wordAddr_n    <=wordAddr_p+1;
              else
                counter_n     <=counter_p+1;
                step_n        <=0;
                tmp           :=key_p(wordAddr_p-1) XOR key(wordAddr_p-6);
                key_n(wordAddr_p)<=tmp;
                wordAddr_n    <=wordAddr_p+1;
                addr_n(0)     <=tmp(15 downto 8);
                addr_n(1)     <=tmp(23 downto 16);
                addr_n(2)     <=tmp(31 downto 24);
                addr_n(3)     <=tmp(7 downto 0);
                state_n       <=restKey;
              end if; 
            end case;
            
          when others=>
            case wordAddr_p is
            when 60=>
              state_n       <=valiKey;
              counter_n     <=0;
              step_n        <=0;
              wordAddr_n    <=0;
            when others=>
              if(step_p=0)then
                step_n        <=step_p+1;
                key_n(wordAddr_p)       <=RCON(counter_p-1) XOR (sByte(3)&sByte(2)&sByte(1)&sByte(0)) XOR key(wordAddr_p-8);
                wordAddr_n    <=wordAddr_p+1;
              elsif ((step_p=1)OR(step_p=2)OR(step_p=5)OR(step_p=6))then
                step_n        <=step_p+1;
                key_n(wordAddr_p)        <=key_p(wordAddr_p-1) XOR key(wordAddr_p-8);
                wordAddr_n    <=wordAddr_p+1;
              elsif step_p=3 then
                step_n        <=step_p+1;
                tmp           :=key_p(wordAddr_p-1) XOR key(wordAddr_p-8);
                key_n(wordAddr_p)<=tmp;
                wordAddr_n    <=wordAddr_p+1;
                addr_n(0)     <=tmp(7 downto 0);
                addr_n(1)     <=tmp(15 downto 8);
                addr_n(2)     <=tmp(23 downto 16);
                addr_n(3)     <=tmp(31 downto 24);
                                state_n       <=restKey;
              elsif step_p=4 then
                step_n        <=step_p+1;
                tmp           :=sByte(3)&sByte(2)&sByte(1)&sByte(0);
                key_n(wordAddr_p)<=tmp XOR key_p(wordAddr_p-8);
                wordAddr_n    <=wordAddr_p+1;        
              else
                counter_n     <=counter_p+1;
                step_n        <=0;
                tmp           :=key_p(wordAddr_p-1)XOR key_p(wordAddr_p-8);
                key_n(wordAddr_p)<=tmp;
                wordAddr_n    <=wordAddr_p+1;
                addr_n(0)     <=tmp(15 downto 8);
                addr_n(1)     <=tmp(23 downto 16);
                addr_n(2)     <=tmp(31 downto 24);
                addr_n(3)     <=tmp(7 downto 0);
                                state_n       <=restKey;
              end if;
            end case;     ----wordAddr_p
          end case;       ----mode_p in calcKey
        
        when restKey=>
          state_n<=calcKey;
          
        when valiKey=>
            counter_n     <=0;
            step_n        <=0;
            wordAddr_n    <=0;
          case startExpansion is
          when '0'=>
            state_n       <=valiKey;
          when others=>
            state_n       <=waitKey;
          end case;             
      end case;         ----state_p
    end process;
    
    process(clk,rst)
      begin
        if(rst='1')then
          keyValid<='0';
        elsif rising_edge(clk)then
          case state_p is
          when valiKey=>
            keyValid<='1';
          when others=>
            keyValid<='0';
          end case;
        end if;
    end process;
    
    process(rst,clk)
      variable round_key: CIPHER_KEY_ARRAY;
      begin
       if(rst='1')then
        for i in 0 to 15 loop
              keyA(i) <= X"AA";
        end loop;
       elsif rising_edge(clk)then
              round_key(0)  := key (to_integer(UNSIGNED(addrA))*4);
              round_key(1)  := key (to_integer(UNSIGNED(addrA))*4+1);
              round_key(2)  := key (to_integer(UNSIGNED(addrA))*4+2);
              round_key(3)  := key (to_integer(UNSIGNED(addrA))*4+3);
        for i in 0 to 3 loop
            for j in 0 to 3 loop
              keyA(i*4+j) <= round_key(i)((j+1)*8-1 downto j*8);
            end loop;
        end loop;
       end if;
    end process;
    
    process(rst,clk)
      variable round_key: CIPHER_KEY_ARRAY;
      begin
       if(rst='1')then
        for i in 0 to 15 loop
              keyB(i) <= X"BB";
        end loop;
       elsif rising_edge(clk)then
              round_key(0)  := key (to_integer(UNSIGNED(addrB))*4);
              round_key(1)  := key (to_integer(UNSIGNED(addrB))*4+1);
              round_key(2)  := key (to_integer(UNSIGNED(addrB))*4+2);
              round_key(3)  := key (to_integer(UNSIGNED(addrB))*4+3);
        for i in 0 to 3 loop
            for j in 0 to 3 loop
              keyB(i*4+j) <= round_key(i)((j+1)*8-1 downto j*8);
            end loop;
        end loop;
       end if;
    end process;

    process(rst,clk)
      variable round_key: CIPHER_KEY_ARRAY;
      begin
       if(rst='1')then
        for i in 0 to 15 loop
              keyC(i) <= X"CC";
        end loop;
       elsif rising_edge(clk)then
              round_key(0)  := key (to_integer(UNSIGNED(addrC))*4);
              round_key(1)  := key (to_integer(UNSIGNED(addrC))*4+1);
              round_key(2)  := key (to_integer(UNSIGNED(addrC))*4+2);
              round_key(3)  := key (to_integer(UNSIGNED(addrC))*4+3);
        for i in 0 to 3 loop
            for j in 0 to 3 loop
              keyC(i*4+j) <= round_key(i)((j+1)*8-1 downto j*8);
            end loop;
        end loop;
       end if;
    end process;
    
--    process(rst,clk)
--      variable round_key: CIPHER_KEY_ARRAY;
--      begin
--       if(rst='1')then
--        for i in 0 to 15 loop
--              keyD(i) <= X"DD";
--        end loop;
--       elsif rising_edge(clk)then
--              round_key(0)  := key (to_integer(UNSIGNED(addrD))*4);
--              round_key(1)  := key (to_integer(UNSIGNED(addrD))*4+1);
--              round_key(2)  := key (to_integer(UNSIGNED(addrD))*4+2);
--              round_key(3)  := key (to_integer(UNSIGNED(addrD))*4+3);
--        for i in 0 to 3 loop
--            for j in 0 to 3 loop
--              keyD(i*4+j) <= round_key(i)((j+1)*8-1 downto j*8);
--            end loop;
--        end loop;
--       end if;
--    end process;
    
  end keyExpansion;
          
                                 
            
