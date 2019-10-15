-------------------------------------------------------------------------------
-- File       : AtlasRd53Ctrl.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Control/Monitor Module
-------------------------------------------------------------------------------
-- This file is part of 'ATLAS RD53 DEV'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'ATLAS RD53 DEV', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;

entity AtlasRd53Ctrl is
   generic (
      TPD_G        : time                  := 1 ns;
      RX_MAPPING_G : Slv2Array(3 downto 0) := (0 => "00", 1 => "01", 2 => "10", 3 => "11"));  -- Set the default RX PHY lane mapping 
   port (
      -- Monitoring Interface (clk160MHz domain)
      clk160MHz       : in  sl;
      rst160MHz       : in  sl;
      autoReadReg     : in  Slv32Array(3 downto 0);
      dataDrop        : in  sl;
      configDrop      : in  sl;
      chBond          : in  sl;
      wrdSent         : in  sl;
      singleHdrDet    : in  sl;
      doubleHdrDet    : in  sl;
      singleHitDet    : in  sl;
      doubleHitDet    : in  sl;
      dlyCfg          : in  Slv9Array(3 downto 0);
      hdrErrDet       : in  slv(3 downto 0);
      bitSlip         : in  slv(3 downto 0);
      linkUp          : in  slv(3 downto 0);
      enable          : out slv(3 downto 0);
      selectRate      : out slv(1 downto 0);
      invData         : out slv(3 downto 0);
      invCmd          : out sl;
      dlyCmd          : out sl;
      rxPhyXbar       : out Slv2Array(3 downto 0);
      enUsrDlyCfg     : out sl;
      usrDlyCfg       : out Slv9Array(3 downto 0);
      slideDlyDir     : out sl;
      slideDlyCfg     : out slv(5 downto 0);
      debugStream     : out sl;
      pllRst          : out sl;
      localRst        : out sl;
      batchSize       : out slv(15 downto 0);
      timerConfig     : out slv(15 downto 0);
      -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end AtlasRd53Ctrl;

architecture rtl of AtlasRd53Ctrl is

   constant STATUS_SIZE_C  : positive := 20;
   constant STATUS_WIDTH_C : positive := 16;

   type RegType is record
      enUsrDlyCfg    : sl;
      usrDlyCfg      : Slv9Array(3 downto 0);
      slideDlyDir    : sl;
      slideDlyCfg    : slv(5 downto 0);
      batchSize      : slv(15 downto 0);
      timerConfig    : slv(15 downto 0);
      pllRst         : sl;
      localRst       : sl;
      debugStream    : sl;
      rxPhyXbar      : Slv2Array(3 downto 0);
      selectRate     : slv(1 downto 0);
      invData        : slv(3 downto 0);
      invCmd         : sl;
      dlyCmd         : sl;
      cntRst         : sl;
      rollOverEn     : slv(STATUS_SIZE_C-1 downto 0);
      enable         : slv(3 downto 0);
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
   end record;

   constant REG_INIT_C : RegType := (
      enUsrDlyCfg    => '0',
      usrDlyCfg      => (others => (others => '0')),
      slideDlyDir    => '0',
      slideDlyCfg    => toSlv(32, 6),
      batchSize      => (others => '0'),
      timerConfig    => (others => '0'),
      pllRst         => '0',
      localRst       => '0',
      debugStream    => '1',
      rxPhyXbar      => RX_MAPPING_G,
      selectRate     => (others => '0'),  -- Default to 1.28 Gb/s ("RD53.SEL_SER_CLK[2:0]" and "selectRate" must be the same)
      -- selectRate     => (others => '1'),  -- Default to 160 Mb/s ("RD53.SEL_SER_CLK[2:0]" and "selectRate" must be the same)
      invData        => (others => '1'),  -- Invert by default
      invCmd         => '0',
      dlyCmd         => '0',
      cntRst         => '1',
      rollOverEn     => (others => '0'),
      enable         => x"F",
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal autoReadRegSync : Slv32Array(3 downto 0);

   signal dlyConfig : Slv9Array(3 downto 0);

   signal statusOut : slv(STATUS_SIZE_C-1 downto 0);
   signal statusCnt : SlVectorArray(STATUS_SIZE_C-1 downto 0, STATUS_WIDTH_C-1 downto 0);

   -- attribute dont_touch      : string;
   -- attribute dont_touch of r : signal is "TRUE";

begin

   comb : process (autoReadRegSync, axilReadMaster, axilRst, axilWriteMaster,
                   dlyConfig, r, statusCnt, statusOut) is
      variable v      : RegType;
      variable axilEp : AxiLiteEndPointType;
   begin
      -- Latch the current value
      v := r;

      -- Reset the strobes
      v.cntRst := '0';

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Map the read registers
      for i in STATUS_SIZE_C-1 downto 0 loop
         axiSlaveRegisterR(axilEp, toSlv((4*i), 12), 0, muxSlVectorArray(statusCnt, i));
      end loop;
      axiSlaveRegisterR(axilEp, x"400", 0, statusOut);

      axiSlaveRegisterR(axilEp, x"410", 0, autoReadRegSync(0));
      axiSlaveRegisterR(axilEp, x"414", 0, autoReadRegSync(1));
      axiSlaveRegisterR(axilEp, x"418", 0, autoReadRegSync(2));
      axiSlaveRegisterR(axilEp, x"41C", 0, autoReadRegSync(3));

      axiSlaveRegisterR(axilEp, x"420", 0, dlyConfig(0));
      axiSlaveRegisterR(axilEp, x"424", 0, dlyConfig(1));
      axiSlaveRegisterR(axilEp, x"428", 0, dlyConfig(2));
      axiSlaveRegisterR(axilEp, x"42C", 0, dlyConfig(3));

      axiSlaveRegister (axilEp, x"800", 0, v.enable);
      axiSlaveRegister (axilEp, x"804", 0, v.invData);
      axiSlaveRegister (axilEp, x"808", 0, v.invCmd);
      axiSlaveRegister (axilEp, x"808", 1, v.dlyCmd);

      axiSlaveRegister (axilEp, x"80C", 0, v.rxPhyXbar(0));
      axiSlaveRegister (axilEp, x"80C", 2, v.rxPhyXbar(1));
      axiSlaveRegister (axilEp, x"80C", 4, v.rxPhyXbar(2));
      axiSlaveRegister (axilEp, x"80C", 6, v.rxPhyXbar(3));
      axiSlaveRegister (axilEp, x"80C", 8, v.selectRate);

      axiSlaveRegister (axilEp, x"810", 0, v.debugStream);
      axiSlaveRegister (axilEp, x"814", 0, v.enUsrDlyCfg);

      axiSlaveRegister (axilEp, x"818", 0, v.slideDlyCfg);
      axiSlaveRegister (axilEp, x"818", 16, v.slideDlyDir);

      axiSlaveRegister (axilEp, x"820", 0, v.usrDlyCfg(0));
      axiSlaveRegister (axilEp, x"824", 0, v.usrDlyCfg(1));
      axiSlaveRegister (axilEp, x"828", 0, v.usrDlyCfg(2));
      axiSlaveRegister (axilEp, x"82C", 0, v.usrDlyCfg(3));

      axiSlaveRegister (axilEp, x"FF0", 0, v.batchSize);
      axiSlaveRegister (axilEp, x"FF0", 16, v.timerConfig);

      axiSlaveRegister (axilEp, x"FF4", 0, v.pllRst);
      axiSlaveRegister (axilEp, x"FF4", 1, v.localRst);

      axiSlaveRegister (axilEp, x"FF8", 0, v.rollOverEn);
      axiSlaveRegister (axilEp, x"FFC", 0, v.cntRst);

      -- Closeout the transaction
      axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

      -- Synchronous Reset
      if (axilRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs
      axilWriteSlave <= r.axilWriteSlave;
      axilReadSlave  <= r.axilReadSlave;
      pllRst         <= r.pllRst;
      batchSize      <= r.batchSize;
      timerConfig    <= r.timerConfig;

   end process comb;

   seq : process (axilClk) is
   begin
      if (rising_edge(axilClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   U_localRst : entity work.RstSync
      generic map (
         TPD_G => TPD_G)
      port map (
         clk      => clk160MHz,
         asyncRst => r.localRst,
         syncRst  => localRst);

   U_enable : entity work.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 4)
      port map (
         clk     => clk160MHz,
         dataIn  => r.enable,
         dataOut => enable);

   U_selectRate : entity work.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 2)
      port map (
         clk     => clk160MHz,
         dataIn  => r.selectRate,
         dataOut => selectRate);

   U_invData : entity work.SynchronizerVector
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 4)
      port map (
         clk     => clk160MHz,
         dataIn  => r.invData,
         dataOut => invData);

   U_invCmd : entity work.Synchronizer
      generic map (
         TPD_G => TPD_G)
      port map (
         clk     => clk160MHz,
         dataIn  => r.invCmd,
         dataOut => invCmd);

   U_dlyCmd : entity work.Synchronizer
      generic map (
         TPD_G => TPD_G)
      port map (
         clk     => clk160MHz,
         dataIn  => r.dlyCmd,
         dataOut => dlyCmd);

   U_debugStream : entity work.Synchronizer
      generic map (
         TPD_G => TPD_G)
      port map (
         clk     => clk160MHz,
         dataIn  => r.debugStream,
         dataOut => debugStream);

   U_enUsrDlyCfg : entity work.Synchronizer
      generic map (
         TPD_G => TPD_G)
      port map (
         clk     => clk160MHz,
         dataIn  => r.enUsrDlyCfg,
         dataOut => enUsrDlyCfg);

   U_slideDlyDir : entity work.Synchronizer
      generic map (
         TPD_G => TPD_G)
      port map (
         clk     => clk160MHz,
         dataIn  => r.slideDlyDir,
         dataOut => slideDlyDir);

   U_slideDlyCfg : entity work.SynchronizerFifo
      generic map (
         TPD_G        => TPD_G,
         DATA_WIDTH_G => 6)
      port map (
         wr_clk => axilClk,
         din    => r.slideDlyCfg,
         rd_clk => clk160MHz,
         dout   => slideDlyCfg);

   GEN_VEC : for i in 3 downto 0 generate

      U_usrDlyCfg : entity work.SynchronizerFifo
         generic map (
            TPD_G        => TPD_G,
            DATA_WIDTH_G => 9)
         port map (
            wr_clk => axilClk,
            din    => r.usrDlyCfg(i),
            rd_clk => clk160MHz,
            dout   => usrDlyCfg(i));

      U_rxPhyXbar : entity work.SynchronizerVector
         generic map (
            TPD_G   => TPD_G,
            WIDTH_G => 2)
         port map (
            clk     => clk160MHz,
            dataIn  => r.rxPhyXbar(i),
            dataOut => rxPhyXbar(i));

      U_autoReadReg : entity work.SynchronizerFifo
         generic map (
            TPD_G        => TPD_G,
            DATA_WIDTH_G => 32)
         port map (
            wr_clk => clk160MHz,
            din    => autoReadReg(i),
            rd_clk => axilClk,
            dout   => autoReadRegSync(i));

      U_dlyCfg : entity work.SynchronizerFifo
         generic map (
            TPD_G        => TPD_G,
            DATA_WIDTH_G => 9)
         port map (
            wr_clk => clk160MHz,
            din    => dlyCfg(i),
            rd_clk => axilClk,
            dout   => dlyConfig(i));

   end generate GEN_VEC;

   U_SyncStatusVector : entity work.SyncStatusVector
      generic map (
         TPD_G          => TPD_G,
         COMMON_CLK_G   => false,
         OUT_POLARITY_G => '1',
         CNT_RST_EDGE_G => false,
         CNT_WIDTH_G    => STATUS_WIDTH_C,
         WIDTH_G        => STATUS_SIZE_C)
      port map (
         -- Input Status bit Signals (wrClk domain)
         statusIn(19 downto 16) => bitSlip,
         statusIn(15 downto 12) => hdrErrDet,
         statusIn(11)           => doubleHitDet,
         statusIn(10)           => singleHitDet,
         statusIn(9)            => doubleHdrDet,
         statusIn(8)            => singleHdrDet,
         statusIn(7)            => wrdSent,
         statusIn(6)            => dataDrop,
         statusIn(5)            => configDrop,
         statusIn(4)            => chBond,
         statusIn(3 downto 0)   => linkUp,
         -- Output Status bit Signals (rdClk domain)  
         statusOut              => statusOut,
         -- Status Bit Counters Signals (rdClk domain) 
         cntRstIn               => r.cntRst,
         rollOverEnIn           => r.rollOverEn,
         cntOut                 => statusCnt,
         -- Clocks and Reset Ports
         wrClk                  => clk160MHz,
         rdClk                  => axilClk);

end rtl;
