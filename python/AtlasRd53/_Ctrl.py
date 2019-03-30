#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# This file is part of the 'ATLAS RD53 FMC DEV'. It is subject to 
# the license terms in the LICENSE.txt file found in the top-level directory 
# of this distribution and at: 
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
# No part of the 'ATLAS RD53 FMC DEV', including this file, may be 
# copied, modified, propagated, or distributed except according to the terms 
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

import pyrogue as pr
        
class Ctrl(pr.Device):
    def __init__(   self,       
            name        = "Ctrl",
            description = "Ctrl Container",
            pollInterval = 1,
            **kwargs):
        super().__init__(name=name, description=description, **kwargs) 

        self.addRemoteVariables(   
            name         = 'LinkUpCnt',
            description  = 'Status counter for link up',
            offset       = 0x000,
            bitSize      = 16,
            mode         = 'RO',
            number       = 4,
            stride       = 4,
            pollInterval = pollInterval,
        )        
        
        self.add(pr.RemoteVariable(
            name         = 'ChBondCnt',
            description  = 'Status counter for channel bonding',
            offset       = 0x010,
            bitSize      = 16,
            mode         = 'RO',
            pollInterval = pollInterval,
        ))        
                
        self.add(pr.RemoteVariable(
            name         = 'ConfigDropCnt',
            description  = 'Increments when config dropped due to back pressure',
            offset       = 0x014,
            bitSize      = 16,
            mode         = 'RO',
            pollInterval = pollInterval,
        ))   

        self.add(pr.RemoteVariable(
            name         = 'DataDropCnt',
            description  = 'Increments when data dropped due to back pressure',
            offset       = 0x018,
            bitSize      = 16,
            mode         = 'RO',
            pollInterval = pollInterval,
        ))           
        
        self.add(pr.RemoteVariable(
            name         = 'LinkUp',
            description  = 'link up',
            offset       = 0x400,
            bitSize      = 4, 
            bitOffset    = 0,
            mode         = 'RO',
            pollInterval = pollInterval,
        ))         
        
        self.add(pr.RemoteVariable(
            name         = 'ChBond',
            description  = 'channel bonding',
            offset       = 0x400,
            bitSize      = 1, 
            bitOffset    = 4,
            mode         = 'RO',
            pollInterval = pollInterval,
        ))        
        
        self.addRemoteVariables(   
            name         = 'AutoRead',
            description  = 'RD53 auto-read register',
            offset       = 0x410,
            bitSize      = 32,
            mode         = 'RO',
            number       = 4,
            stride       = 4,
            pollInterval = pollInterval,
        )          
        
        self.add(pr.RemoteVariable(
            name         = 'EnLane', 
            description  = 'Enable Lane Mask',
            offset       = 0x800,
            bitSize      = 4, 
            mode         = 'RW',
        )) 

        self.add(pr.RemoteVariable(
            name         = 'InvData', 
            description  = 'Invert the serial data bits',
            offset       = 0x804,
            bitSize      = 4, 
            mode         = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name         = 'InvCmd', 
            description  = 'Invert the serial CMD bit',
            offset       = 0x808,
            bitSize      = 1, 
            mode         = 'RW',
        ))        
        
        for i in range(4):
            self.add(pr.RemoteVariable(
                name         = ('RxPhyXbar[%d]'%i), 
                description  = 'RD53 Lane 4:4 lane crossbar configuration',
                offset       = 0x80C,
                bitOffset    = (2*i),
                bitSize      = 2, 
                mode         = 'RW',
            ))             
        
        self.add(pr.RemoteVariable(
            name         = 'DebugStream', 
            description  = 'Enables the interleaving of autoreg and read responses into the dataStream path',
            offset       = 0x810,
            bitSize      = 1, 
            mode         = 'RW',
        ))         

        self.add(pr.RemoteVariable(
            name         = 'BatchSize', 
            description  = 'Number of 64-bit (8 bytes) words to batch together into a AXIS frame',
            offset       = 0xFF0,
            bitSize      = 16, 
            bitOffset    = 0,
            mode         = 'RW',
            units        = '8Bytes',
            base         = pr.UInt,
        ))  

        self.add(pr.RemoteVariable(
            name         = 'TimerConfig', 
            description  = 'Batcher timer configuration',
            offset       = 0xFF0,
            bitSize      = 16, 
            bitOffset    = 16,
            mode         = 'RW',
            units        = '6.4ns',
            base         = pr.UInt,
        ))   
        
        self.add(pr.RemoteCommand(   
            name         = 'PllRst',
            description  = 'FPGA Internal PLL reset',
            offset       = 0xFF4,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))         

        self.add(pr.RemoteVariable(
            name         = 'RollOverEn', 
            description  = 'Rollover enable for status counters',
            offset       = 0xFF8,
            bitSize      = 7, 
            mode         = 'RW',
        ))        
        
        self.add(pr.RemoteCommand(   
            name         = 'CntRst',
            description  = 'Status counter reset',
            offset       = 0xFFC,
            bitSize      = 1,
            function     = lambda cmd: cmd.post(1),
            hidden       = False,
        ))  

    def hardReset(self):
        self.CntRst()

    def softReset(self):
        self.CntRst()

    def countReset(self):
        self.CntRst()
     