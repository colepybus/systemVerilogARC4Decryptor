Built a hardware ARC4 (RC4) decryption and key-cracking engine in SystemVerilog on the DE1-SoC Intel FPGA board. Simulated and verified in Questa, then synthesized in Quartus.

The design uses FSM-controlled modules for each cipher stage (S-array init, KSA, PRGA). They are linked by a ready/enable handshake and share on-chip M10K memory. Parallel cracking cores brute-force the 24-bit key space and show the recovered key on the HEX displays.
