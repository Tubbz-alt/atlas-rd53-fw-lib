------------------------------------------------------------------------------
-- Copyright (c) 2012 Xilinx, Inc.
-- This design is confidential and proprietary of Xilinx, All Rights Reserved.
------------------------------------------------------------------------------
--   ____  ____
--  /   /\/   /
-- /___/  \  /   Vendor:                Xilinx
-- \   \   \/    Version:               1.0
--  \   \        Filename:              serdes_1_to_468_idelay_ddr.v
--  /   /        Date Last Modified:    Mar 30, 2016
-- /___/   /\    Date Created:          Mar 5, 2011
-- \   \  /  \
--  \___\/\___\
-- 
--Device:   7 Series
--Purpose:     1 to 4 DDR data receiver.
--    Data formatting is set by the DATA_FORMAT parameter. 
--    PER_CLOCK (default) format receives bits for 0, 1, 2 .. on the same sample edge
--    PER_CHANL format receives bits for 0, 4, 8 ..  on the same sample edge
--
--Reference:   
--    
--Revision History:
--    Rev 1.0 - First created (nicks)
--
------------------------------------------------------------------------------
--
--  Disclaimer: 
--
--    This disclaimer is not a license and does not grant any rights to the materials 
--              distributed herewith. Except as otherwise provided in a valid license issued to you 
--              by Xilinx, and to the maximum extent permitted by applicable law: 
--              (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND WITH ALL FAULTS, 
--              AND XILINX HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, 
--              INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT, OR 
--              FITNESS FOR ANY PARTICULAR PURPOSE; and (2) Xilinx shall not be liable (whether in contract 
--              or tort, including negligence, or under any other theory of liability) for any loss or damage 
--              of any kind or nature related to, arising under or in connection with these materials, 
--              including for any direct, or any indirect, special, incidental, or consequential loss 
--              or damage (including loss of data, profits, goodwill, or any type of loss or damage suffered 
--              as a result of any action brought by a third party) even if such damage or loss was 
--              reasonably foreseeable or Xilinx had been advised of the possibility of the same.
--
--  Critical Applications:
--
--    Xilinx products are not designed or intended to be fail-safe, or for use in any application 
--    requiring fail-safe performance, such as life-support or safety devices or systems, 
--    Class III medical devices, nuclear facilities, applications related to the deployment of airbags,
--    or any other applications that could lead to death, personal injury, or severe property or 
--    environmental damage (individually and collectively, "Critical Applications"). Customer assumes 
--    the sole risk and liability of any use of Xilinx products in Critical Applications, subject only 
--    to applicable laws and regulations governing limitations on product liability.
--
--  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS PART OF THIS FILE AT ALL TIMES.
--
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;

entity serdes_1_to_468_idelay_ddr is
   generic (
      TPD_G                 : time    := 1 ns;
      XIL_DEVICE_G          : string  := "ULTRASCALE";
      S                     : integer := 8;  -- Set the serdes factor to 4, 6 or 8
      D                     : integer := 8;  -- Set the number of inputs
      REF_FREQ              : real    := 200.0;  -- Parameter to set reference frequency used by idelay controller
      HIGH_PERFORMANCE_MODE : string  := "FALSE";  -- Parameter to set HIGH_PERFORMANCE_MODE of input delays to reduce jitter
      DATA_FORMAT           : string  := "PER_CLOCK");  -- Used to determine method for mapping input parallel word to output serial words
   port (
      datain_p       : in  std_logic_vector(D-1 downto 0);  -- Input from LVDS receiver pin
      datain_n       : in  std_logic_vector(D-1 downto 0);  -- Input from LVDS receiver pin
      reset          : in  std_logic;   -- Reset line
      idelay_rdy     : in  std_logic;   -- input delays are ready
      rxclk          : in  std_logic;   -- Global/BUFIO rx clock network
      system_clk     : in  std_logic;   -- Global/Regional clock output
      bit_rate_value : in  std_logic_vector(15 downto 0) := x"1280";  -- Bit rate in Mbps, eg X"0585
      dcd_correct    : in  std_logic                     := '0';  -- '0' = square, '1' = assume 10% DCD
      rx_lckd        : out std_logic;   -- 
      rx_data        : out std_logic_vector((S*D)-1 downto 0);  -- Output data
      bit_time_value : out std_logic_vector(4 downto 0);  -- Calculated bit time value for slave devices
      debug          : out std_logic_vector(10*D+18 downto 0);  -- Debug bus
      eye_info       : out std_logic_vector(32*D-1 downto 0);  -- Eye info
      m_delay_1hot   : out std_logic_vector(32*D-1 downto 0);  -- Master delay control value as a one-hot vector
      clock_sweep    : out std_logic_vector(31 downto 0));  -- clock Eye info
end serdes_1_to_468_idelay_ddr;

architecture arch_serdes_1_to_468_idelay_ddr of serdes_1_to_468_idelay_ddr is

   component delay_controller_wrap is
      generic (
         S : integer := 4);             -- Set the number of bits
      port (
         m_datain              : in  std_logic_vector(S-1 downto 0);  -- Inputs from master serdes
         s_datain              : in  std_logic_vector(S-1 downto 0);  -- Inputs from slave serdes
         enable_phase_detector : in  std_logic;  -- Enables the phase detector logic when high
         enable_monitor        : in  std_logic;  -- Enables the eye monitoring logic when high
         reset                 : in  std_logic;  -- Reset line synchronous to clk
         clk                   : in  std_logic;  -- Global/Regional clock 
         c_delay_in            : in  std_logic_vector(4 downto 0);  -- delay value found on clock line
         m_delay_out           : out std_logic_vector(4 downto 0);  -- Master delay control value
         s_delay_out           : out std_logic_vector(4 downto 0);  -- Master delay control value
         data_out              : out std_logic_vector(S-1 downto 0);  -- Output data
         results               : out std_logic_vector(31 downto 0);  -- eye monitor result data
         m_delay_1hot          : out std_logic_vector(31 downto 0);  -- Master delay control value as a one-hot vector
         debug                 : out std_logic_vector(1 downto 0);  -- debug data
         del_mech              : in  std_logic;  -- changes delay mechanism slightly at higher bit rates
         bt_val                : in  std_logic_vector(4 downto 0));  -- Calculated bit time value for slave devices
   end component;

   signal m_delay_val_in     : std_logic_vector(9*D-1 downto 0) := (others => '0');
   signal s_delay_val_in     : std_logic_vector(9*D-1 downto 0) := (others => '0');
   signal m_delay_val_out    : std_logic_vector(9*D-1 downto 0) := (others => '0');
   signal s_delay_val_out    : std_logic_vector(9*D-1 downto 0) := (others => '0');
   signal cdataout           : std_logic_vector(3 downto 0);
   signal bsstate            : std_logic_vector(1 downto 0);
   signal bcount             : std_logic_vector(3 downto 0);
   signal clk_iserdes_data_d : std_logic_vector(3 downto 0);
   signal enable             : std_logic;
   signal flag1              : std_logic;
   signal state2_count       : std_logic_vector(4 downto 0)     := "00000";
   signal rx_lckd_int        : std_logic;
   signal rx_lckd_intd4      : std_logic;
   signal not_rx_lckd_intd4  : std_logic;
   signal rx_data_in_p       : std_logic_vector(D-1 downto 0);
   signal rx_data_in_n       : std_logic_vector(D-1 downto 0);
   signal rx_data_in_m       : std_logic_vector(D-1 downto 0);
   signal rx_data_in_s       : std_logic_vector(D-1 downto 0);
   signal rx_data_in_md      : std_logic_vector(D-1 downto 0);
   signal rx_data_in_sd      : std_logic_vector(D-1 downto 0);
   signal mdataout           : std_logic_vector(S*D-1 downto 0);
   signal mdataoutd          : std_logic_vector(S*D-1 downto 0);
   signal sdataout           : std_logic_vector(S*D-1 downto 0);
   signal m_serdes           : std_logic_vector(8*D-1 downto 0) := (others => '0');
   signal s_serdes           : std_logic_vector(8*D-1 downto 0) := (others => '0');
   signal m_serdesPhy        : std_logic_vector(8*D-1 downto 0) := (others => '0');
   signal s_serdesPhy        : std_logic_vector(8*D-1 downto 0) := (others => '0');   
   signal system_clk_int     : std_logic;
   signal data_different     : std_logic;
   signal bt_val             : std_logic_vector(4 downto 0);
   signal su_locked          : std_logic;
   signal m_count            : std_logic_vector(5 downto 0);
   signal c_sweep_delay      : std_logic_vector(4 downto 0)     := "00000";
   signal c_found_val        : std_logic_vector(4 downto 0);
   signal c_found_offset     : std_logic_vector(4 downto 0);
   signal temp_shift         : std_logic_vector(31 downto 0);
   signal rx_clk_in_p        : std_logic;
   signal rx_clk_in_pc       : std_logic;
   signal rx_clk_in_pd       : std_logic;
   signal rst_iserdes        : std_logic;
   signal clock_sweep_int    : std_logic_vector(31 downto 0);
   signal zflag              : std_logic;
   signal del_mech           : std_logic;
   signal bt_val_d2          : std_logic_vector(4 downto 0);
   signal del_debug          : std_logic_vector(2*D-1 downto 0);
   signal initial_delay      : std_logic_vector(4 downto 0);

   constant RX_SWAP_MASK : std_logic_vector(D-1 downto 0) := (others => '0');  -- pinswap mask for input data bits (0 = no swap (default), 1 = swap). Allows inputs to be connected the wrong way round to ease PCB routing.

   attribute IODELAY_GROUP : string;


begin

   rx_lckd        <= not(reset);  -- not not_rx_lckd_intd4 and su_locked ;
   bit_time_value <= bt_val;
   system_clk_int <= system_clk;        -- theim: use external 
   clock_sweep    <= clock_sweep_int;
   bt_val_d2      <= '0' & bt_val(4 downto 1);
   cdataout       <= m_serdes(3 downto 0);  -- theim: hardcoded

   loop11a : if REF_FREQ <= 210.0 generate  -- Generate tap number to be used for input bit rate (200 MHz ref clock)
      bt_val <= "00111" when bit_rate_value > X"1984" else
                "01000" when bit_rate_value > X"1717" else
                "01001" when bit_rate_value > X"1514" else
                "01010" when bit_rate_value > X"1353" else
                "01011" when bit_rate_value > X"1224" else
                "01100" when bit_rate_value > X"1117" else
                "01101" when bit_rate_value > X"1027" else
                "01110" when bit_rate_value > X"0951" else
                "01111" when bit_rate_value > X"0885" else
                "10000" when bit_rate_value > X"0828" else
                "10001" when bit_rate_value > X"0778" else
                "10010" when bit_rate_value > X"0733" else
                "10011" when bit_rate_value > X"0694" else
                "10100" when bit_rate_value > X"0658" else
                "10101" when bit_rate_value > X"0626" else
                "10110" when bit_rate_value > X"0597" else
                "10111" when bit_rate_value > X"0570" else
                "11000" when bit_rate_value > X"0546" else
                "11001" when bit_rate_value > X"0524" else
                "11010" when bit_rate_value > X"0503" else
                "11011" when bit_rate_value > X"0484" else
                "11100" when bit_rate_value > X"0466" else
                "11101" when bit_rate_value > X"0450" else
                "11110" when bit_rate_value > X"0435" else
                "11111";                -- min bit rate 420 Mbps

      del_mech <= '1' when bt_val < "10110" else '0';  -- adjust delay mechanism when tap values are low enough 

   end generate;

   loop11b : if REF_FREQ > 210.0 generate  -- Generate tap number to be used for input bit rate (300 MHz ref clock) 
      bt_val <= "01010" when (dcd_correct = '0' and bit_rate_value > X"2030") or (dcd_correct = '1' and bit_rate_value > X"1845") else
                "01011" when (dcd_correct = '0' and bit_rate_value > X"1836") or (dcd_correct = '1' and bit_rate_value > X"1669") else
                "01100" when (dcd_correct = '0' and bit_rate_value > X"1675") or (dcd_correct = '1' and bit_rate_value > X"1523") else
                "01101" when (dcd_correct = '0' and bit_rate_value > X"1541") or (dcd_correct = '1' and bit_rate_value > X"1401") else
                "01110" when (dcd_correct = '0' and bit_rate_value > X"1426") or (dcd_correct = '1' and bit_rate_value > X"1297") else
                "01111" when (dcd_correct = '0' and bit_rate_value > X"1328") or (dcd_correct = '1' and bit_rate_value > X"1207") else
                "10000" when (dcd_correct = '0' and bit_rate_value > X"1242") or (dcd_correct = '1' and bit_rate_value > X"1129") else
                "10001" when (dcd_correct = '0' and bit_rate_value > X"1167") or (dcd_correct = '1' and bit_rate_value > X"1061") else
                "10010" when (dcd_correct = '0' and bit_rate_value > X"1100") or (dcd_correct = '1' and bit_rate_value > X"0999") else
                "10011" when (dcd_correct = '0' and bit_rate_value > X"1040") or (dcd_correct = '1' and bit_rate_value > X"0946") else
                "10100" when (dcd_correct = '0' and bit_rate_value > X"0987") or (dcd_correct = '1' and bit_rate_value > X"0897") else
                "10101" when (dcd_correct = '0' and bit_rate_value > X"0939") or (dcd_correct = '1' and bit_rate_value > X"0853") else
                "10110" when (dcd_correct = '0' and bit_rate_value > X"0895") or (dcd_correct = '1' and bit_rate_value > X"0814") else
                "10111" when (dcd_correct = '0' and bit_rate_value > X"0855") or (dcd_correct = '1' and bit_rate_value > X"0777") else
                "11000" when (dcd_correct = '0' and bit_rate_value > X"0819") or (dcd_correct = '1' and bit_rate_value > X"0744") else
                "11001" when (dcd_correct = '0' and bit_rate_value > X"0785") or (dcd_correct = '1' and bit_rate_value > X"0714") else
                "11010" when (dcd_correct = '0' and bit_rate_value > X"0754") or (dcd_correct = '1' and bit_rate_value > X"0686") else
                "11011" when (dcd_correct = '0' and bit_rate_value > X"0726") or (dcd_correct = '1' and bit_rate_value > X"0660") else
                "11100" when (dcd_correct = '0' and bit_rate_value > X"0700") or (dcd_correct = '1' and bit_rate_value > X"0636") else
                "11101" when (dcd_correct = '0' and bit_rate_value > X"0675") or (dcd_correct = '1' and bit_rate_value > X"0614") else
                "11110" when (dcd_correct = '0' and bit_rate_value > X"0652") or (dcd_correct = '1' and bit_rate_value > X"0593") else
                "11111";                -- min bit rate 631 Mbps

      del_mech <= '1' when bt_val < "10110" else '0';  -- adjust delay mechanism when tap values are low enough 

   end generate;

   process (system_clk_int)
   begin  -- sweep data
      if system_clk_int'event and system_clk_int = '1' then
         if su_locked = '0' then
            c_sweep_delay     <= "00000";
            temp_shift        <= (0      => '1', others => '0');
            clock_sweep_int   <= (others => '0');
            zflag             <= '0';
            not_rx_lckd_intd4 <= '1';
            rx_lckd_intd4     <= '0';
            initial_delay     <= "00000";
         else
            not_rx_lckd_intd4 <= not rx_lckd_intd4;
            if state2_count = "11111" then
               if c_sweep_delay /= bt_val then
                  if zflag = '0' then
                     c_sweep_delay <= c_sweep_delay + 1;
                     temp_shift    <= temp_shift(30 downto 0) & temp_shift(31);
                  else
                     zflag <= '0';
                  end if;
               else
                  c_sweep_delay <= "00000";
                  zflag         <= '1';  -- need to check tap 0 twice bacause of wraparound
                  temp_shift    <= (0 => '1', others => '0');
               end if;
               if zflag = '0' then
                  if data_different = '1' then
                     clock_sweep_int <= clock_sweep_int and not temp_shift;
                     if initial_delay = "00000" then
                        rx_lckd_intd4 <= '1';
                        if c_sweep_delay < '0' & bt_val(4 downto 1) then  -- choose the lowest delay value to minimise jitter
                           initial_delay <= c_sweep_delay + ('0' & bt_val(4 downto 1));
                        else
                           initial_delay <= c_sweep_delay - ('0' & bt_val(4 downto 1));
                        end if;
                     end if;
                  else
                     clock_sweep_int <= clock_sweep_int or temp_shift;
                  end if;
               end if;
            end if;
         end if;
      end if;
   end process;

   process (idelay_rdy, reset, system_clk_int)
   begin
      if reset = '1' or idelay_rdy = '0' then
         su_locked   <= '0';
         m_count     <= "000000";
         rst_iserdes <= '1';
      elsif system_clk_int'event and system_clk_int = '1' then  -- startup delay
         if m_count = "111100" then
            rst_iserdes <= '0';
            m_count     <= m_count + 1;
         elsif m_count = "111111" then
            su_locked <= '1';
         else
            m_count <= m_count + 1;
         end if;
      end if;
   end process;

   process (system_clk_int)
   begin  -- sweep data
      if system_clk_int'event and system_clk_int = '1' then
         if su_locked = '0' then
            state2_count <= "00000";
         else
            state2_count <= state2_count + 1;
            if state2_count = "00000" then
               clk_iserdes_data_d <= cdataout;
            elsif state2_count <= "01000" then
               data_different <= '0';
            elsif cdataout /= clk_iserdes_data_d then
               data_different <= '1';
            end if;
         end if;
      end if;
   end process;

   loop3 : for i in 0 to D-1 generate

      dc_inst : delay_controller_wrap
         generic map (
            S => S)
         port map (
            m_datain              => mdataout(S*i+S-1 downto S*i),
            s_datain              => sdataout(S*i+S-1 downto S*i),
            enable_phase_detector => '0',
            enable_monitor        => '0',
            --reset        => not_rx_lckd_intd4,
            reset                 => reset,
            clk                   => system_clk_int,
            --c_delay_in      => initial_delay,
            c_delay_in            => "10000",
            m_delay_out           => m_delay_val_in(9*i+8 downto 9*i+4),
            s_delay_out           => s_delay_val_in(9*i+8 downto 9*i+4),
            data_out              => mdataoutd(S*i+S-1 downto S*i),
            bt_val                => bt_val,
            del_mech              => del_mech,
            debug                 => del_debug(i*2+1 downto i*2),
            m_delay_1hot          => m_delay_1hot(32*i+31 downto 32*i),
            results               => eye_info(32*i+31 downto 32*i));

   end generate;

   -- Data bit Receivers 
   loop0 : for i in 0 to D-1 generate
      attribute IODELAY_GROUP of idelay_m : label is "rd53_aurora";
      attribute IODELAY_GROUP of idelay_s : label is "rd53_aurora";
   begin
      loop1 : for j in 0 to S-1 generate  -- Assign data bits to correct serdes according to required format
         loop1a : if DATA_FORMAT = "PER_CLOCK" generate
            rx_data(D*j+i) <= mdataoutd(S*i+j);
         end generate;
         loop1b : if DATA_FORMAT = "PER_CHANL" generate
            rx_data(S*i+j) <= mdataoutd(S*i+j);
         end generate;
      end generate;

      data_in : IBUFDS_DIFF_OUT
         port map (
            I  => datain_p(i),
            IB => datain_n(i),
            O  => rx_data_in_p(i),
            OB => rx_data_in_n(i));

      rx_data_in_m(i) <= rx_data_in_p(i) xor RX_SWAP_MASK(i);
      rx_data_in_s(i) <= rx_data_in_n(i) xor RX_SWAP_MASK(i);

      idelay_m : IDELAYE3
         generic map (
            -- DELAY_FORMAT     => "TIME",
            DELAY_FORMAT     => "COUNT",
            SIM_DEVICE       => XIL_DEVICE_G,
            DELAY_VALUE      => 0,
            REFCLK_FREQUENCY => REF_FREQ,
            CASCADE          => "NONE",
            DELAY_SRC        => "IDATAIN",
            DELAY_TYPE       => "VAR_LOAD")
         port map(
            DATAOUT     => rx_data_in_md(i),
            CLK         => system_clk_int,
            CE          => '0',
            INC         => '0',
            DATAIN      => '0',
            IDATAIN     => rx_data_in_m(i),
            LOAD        => '1',
            -- EN_VTC      => '1',
            EN_VTC      => '0',
            RST         => '0',
            CASC_IN     => '0',
            CASC_RETURN => '0',
            CNTVALUEIN  => m_delay_val_in(9*i+8 downto 9*i),
            CNTVALUEOUT => m_delay_val_out(9*i+8 downto 9*i));

      iserdes_m : ISERDESE3
         generic map (
            DATA_WIDTH        => S,
            FIFO_ENABLE       => "FALSE",
            FIFO_SYNC_MODE    => "FALSE",
            IS_CLK_B_INVERTED => '1',
            IS_CLK_INVERTED   => '0',
            IS_RST_INVERTED   => '0',
            SIM_DEVICE        => XIL_DEVICE_G)
         port map (
            Q(7)        => m_serdesPhy(S*i+7),
            Q(6)        => m_serdesPhy(S*i+6),
            Q(5)        => m_serdesPhy(S*i+5),
            Q(4)        => m_serdesPhy(S*i+4),
            Q(3)        => m_serdesPhy(S*i+3),
            Q(2)        => m_serdesPhy(S*i+2),
            Q(1)        => m_serdesPhy(S*i+1),
            Q(0)        => m_serdesPhy(S*i+0),
            CLK         => rxclk,
            CLK_B       => rxclk,
            CLKDIV      => system_clk_int,
            D           => rx_data_in_md(i),
            RST         => rst_iserdes,
            FIFO_RD_CLK => '0',
            FIFO_RD_EN  => '0',
            FIFO_EMPTY  => open);

      idelay_s : IDELAYE3
         generic map (
            -- DELAY_FORMAT     => "TIME",
            DELAY_FORMAT     => "COUNT",
            SIM_DEVICE       => XIL_DEVICE_G,
            DELAY_VALUE      => 0,
            REFCLK_FREQUENCY => REF_FREQ,
            CASCADE          => "NONE",
            DELAY_SRC        => "IDATAIN",
            DELAY_TYPE       => "VAR_LOAD")
         port map(
            DATAOUT     => rx_data_in_sd(i),
            CLK         => system_clk_int,
            CE          => '0',
            INC         => '0',
            DATAIN      => '0',
            IDATAIN     => rx_data_in_s(i),
            LOAD        => '1',
            -- EN_VTC      => '1',
            EN_VTC      => '0',
            RST         => '0',
            CASC_IN     => '0',
            CASC_RETURN => '0',
            CNTVALUEIN  => s_delay_val_in(9*i+8 downto 9*i),
            CNTVALUEOUT => s_delay_val_out(9*i+8 downto 9*i));

      iserdes_s : ISERDESE3
         generic map (
            DATA_WIDTH        => S,
            FIFO_ENABLE       => "FALSE",
            FIFO_SYNC_MODE    => "FALSE",
            IS_CLK_B_INVERTED => '1',
            IS_CLK_INVERTED   => '0',
            IS_RST_INVERTED   => '0',
            SIM_DEVICE        => XIL_DEVICE_G)
         port map (
            Q(7)        => s_serdesPhy(S*i+7),
            Q(6)        => s_serdesPhy(S*i+6),
            Q(5)        => s_serdesPhy(S*i+5),
            Q(4)        => s_serdesPhy(S*i+4),
            Q(3)        => s_serdesPhy(S*i+3),
            Q(2)        => s_serdesPhy(S*i+2),
            Q(1)        => s_serdesPhy(S*i+1),
            Q(0)        => s_serdesPhy(S*i+0),
            CLK         => rxclk,
            CLK_B       => rxclk,
            CLKDIV      => system_clk_int,
            D           => rx_data_in_sd(i),
            RST         => rst_iserdes,
            FIFO_RD_CLK => '0',
            FIFO_RD_EN  => '0',
            FIFO_EMPTY  => open);

      -- sort out necessary bits from iserdes
      loop0a : if S = 4 generate
         mdataout(4*i+3 downto 4*i) <= m_serdes(8*i+7 downto 8*i+4);
         sdataout(4*i+3 downto 4*i) <= not s_serdes(8*i+7 downto 8*i+4);
      end generate;

      loop0b : if S = 6 generate
         mdataout(6*i+5 downto 6*i) <= m_serdes(8*i+7 downto 8*i+2);
         sdataout(6*i+5 downto 6*i) <= not s_serdes(8*i+7 downto 8*i+2);
      end generate;

      loop0c : if S = 8 generate
         mdataout(8*i+7 downto 8*i) <= m_serdes(8*i+7 downto 8*i);
         sdataout(8*i+7 downto 8*i) <= not s_serdes(8*i+7 downto 8*i);
      end generate;

   end generate;
   
   process(system_clk_int)
   begin
      if rising_edge(system_clk_int) then
         -- Register to help make timing
         m_serdes <= m_serdesPhy after TPD_G;
         s_serdes <= s_serdesPhy after TPD_G;
      end if;
   end process;
      
   

end arch_serdes_1_to_468_idelay_ddr;