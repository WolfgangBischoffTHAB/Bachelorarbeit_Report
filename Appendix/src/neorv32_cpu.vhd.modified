-- ================================================================================ --
-- NEORV32 CPU - CPU Top Entity                                                     --
-- -------------------------------------------------------------------------------- --
-- HQ:           https://github.com/stnolting/neorv32                               --
-- Data Sheet:   https://stnolting.github.io/neorv32                                --
-- User Guide:   https://stnolting.github.io/neorv32/ug                             --
-- Software Ref: https://stnolting.github.io/neorv32/sw/files.html                  --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

use std.textio.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
--use ieee.numeric_std_unsigned.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu is
  generic (
    -- General --
    HART_ID             : natural range 0 to 1023;        -- hardware thread ID
    BOOT_ADDR           : std_ulogic_vector(31 downto 0); -- CPU boot address
    DEBUG_PARK_ADDR     : std_ulogic_vector(31 downto 0); -- CPU debug mode parking loop entry address
    DEBUG_EXC_ADDR      : std_ulogic_vector(31 downto 0); -- CPU debug mode exception entry address
    -- RISC-V ISA Extensions --
    RISCV_ISA_C         : boolean;                        -- compressed extension
    RISCV_ISA_E         : boolean;                        -- embedded RF extension
    RISCV_ISA_M         : boolean;                        -- mul/div extension
    RISCV_ISA_U         : boolean;                        -- user mode extension
    RISCV_ISA_Zaamo     : boolean;                        -- atomic read-modify-write operations extension
    RISCV_ISA_Zalrsc    : boolean;                        -- atomic reservation-set operations extension
    RISCV_ISA_Zcb       : boolean;                        -- additional code size reduction instructions
    RISCV_ISA_Zba       : boolean;                        -- shifted-add bit-manipulation extension
    RISCV_ISA_Zbb       : boolean;                        -- basic bit-manipulation extension
    RISCV_ISA_Zbkb      : boolean;                        -- bit-manipulation instructions for cryptography
    RISCV_ISA_Zbkc      : boolean;                        -- carry-less multiplication instructions
    RISCV_ISA_Zbkx      : boolean;                        -- cryptography crossbar permutation extension
    RISCV_ISA_Zbs       : boolean;                        -- single-bit bit-manipulation extension
    RISCV_ISA_Zfinx     : boolean;                        -- 32-bit floating-point extension
    RISCV_ISA_Zibi      : boolean;                        -- branch with immediate
    RISCV_ISA_Zicntr    : boolean;                        -- base counters
    RISCV_ISA_Zicond    : boolean;                        -- integer conditional operations
    RISCV_ISA_Zihpm     : boolean;                        -- hardware performance monitors
    RISCV_ISA_Zknd      : boolean;                        -- cryptography NIST AES decryption extension
    RISCV_ISA_Zkne      : boolean;                        -- cryptography NIST AES encryption extension
    RISCV_ISA_Zknh      : boolean;                        -- cryptography NIST hash extension
    RISCV_ISA_Zksed     : boolean;                        -- ShangMi hash extension
    RISCV_ISA_Zksh      : boolean;                        -- ShangMi block cipher extension
    RISCV_ISA_Zmmul     : boolean;                        -- multiply-only M sub-extension
    RISCV_ISA_Zxcfu     : boolean;                        -- custom (instr.) functions unit
    RISCV_ISA_Sdext     : boolean;                        -- external debug mode extension
    RISCV_ISA_Sdtrig    : boolean;                        -- trigger module extension
    RISCV_ISA_Smpmp     : boolean;                        -- physical memory protection
    -- Tuning Options --
    CPU_TRACE_EN        : boolean;                        -- enable CPU execution trace generator
    CPU_CONSTT_BR_EN    : boolean;                        -- constant-time branches
    CPU_FAST_MUL_EN     : boolean;                        -- use DSPs for M extension's multiplier
    CPU_FAST_SHIFT_EN   : boolean;                        -- use barrel shifter for shift operations
    CPU_RF_HW_RST_EN    : boolean;                        -- enable full hardware reset for register file
    -- Physical Memory Protection (PMP) --
    PMP_NUM_REGIONS     : natural range 0 to 16;          -- number of regions (0..16)
    PMP_MIN_GRANULARITY : natural;                        -- minimal region granularity in bytes, has to be a power of 2, min 4 bytes
    PMP_TOR_MODE_EN     : boolean;                        -- enable TOR mode
    PMP_NAP_MODE_EN     : boolean;                        -- enable NAPOT/NA4 modes
    -- Hardware Performance Monitors (HPM) --
    HPM_NUM_CNTS        : natural range 0 to 13;          -- number of implemented HPM counters (0..13)
    HPM_CNT_WIDTH       : natural range 0 to 64;          -- total size of HPM counters (0..64)
    -- Trigger Module (TM) --
    NUM_HW_TRIGGERS     : natural range 0 to 16           -- number of hardware triggers
  );
  port (
    -- global control --
    clk_i      : in  std_ulogic;                     -- global clock, rising edge
    rstn_i     : in  std_ulogic;                     -- global reset, low-active, async
    -- status --
    trace_o    : out trace_port_t;                   -- execution trace port (enabled when CPU_TRACE_EN = true)
    sleep_o    : out std_ulogic;                     -- CPU is in sleep mode
    -- interrupts --
    msi_i      : in  std_ulogic;                     -- RISC-V machine software interrupt
    mei_i      : in  std_ulogic;                     -- RISC-V machine external interrupt
    mti_i      : in  std_ulogic;                     -- RISC-V machine timer interrupt
    firq_i     : in  std_ulogic_vector(15 downto 0); -- custom fast interrupts
    dbi_i      : in  std_ulogic;                     -- RISC-V debug halt request interrupt
    -- instruction bus interface --
    ibus_req_o : out bus_req_t;                      -- request bus
    ibus_rsp_i : in  bus_rsp_t;                      -- response bus
    -- data bus interface --
    dbus_req_o : out bus_req_t;                      -- request bus
    dbus_rsp_i : in  bus_rsp_t                       -- response bus
  );
end neorv32_cpu;

architecture neorv32_cpu_rtl of neorv32_cpu is

  -- auto-configuration --
  constant riscv_a_c   : boolean := RISCV_ISA_Zaamo and RISCV_ISA_Zalrsc; -- A: atomic memory operations
  constant riscv_b_c   : boolean := RISCV_ISA_Zba and RISCV_ISA_Zbb and RISCV_ISA_Zbs; -- B: bit manipulation
  constant riscv_zcb_c : boolean := RISCV_ISA_C and RISCV_ISA_Zcb; -- Zcb: additional compressed instructions
  constant riscv_zkt_c : boolean := CPU_FAST_SHIFT_EN; -- Zkt: data-independent execution time for cryptography operations
  constant riscv_zkn_c : boolean := RISCV_ISA_Zbkb and RISCV_ISA_Zbkc and RISCV_ISA_Zbkx and
                                    RISCV_ISA_Zkne and RISCV_ISA_Zknd and RISCV_ISA_Zknh; -- Zkn: NIST suite
  constant riscv_zks_c : boolean := RISCV_ISA_Zbkb and RISCV_ISA_Zbkc and RISCV_ISA_Zbkx and
                                    RISCV_ISA_Zksh and RISCV_ISA_Zksed; -- Zks: ShangMi suite

  -- external CSR interface read-back --
  signal xcsr_tm, xcsr_cnt, xcsr_pmp, xcsr_alu, xcsr_res : std_ulogic_vector(XLEN-1 downto 0);

  -- local signals --
  signal ctrl        : ctrl_bus_t;                         -- main control bus
  signal frontend    : if_bus_t;                           -- instruction-fetch interface
  signal hwtrig      : std_ulogic;                         -- hardware trigger firing
  signal rf_wdata    : std_ulogic_vector(XLEN-1 downto 0); -- x register file write data
  signal m_rf_wdata  : std_ulogic_vector(XLEN-1 downto 0); -- m register file write data
  signal rs1         : std_ulogic_vector(XLEN-1 downto 0); -- source register 1
  signal rs2         : std_ulogic_vector(XLEN-1 downto 0); -- source register 2
  signal alu_res     : std_ulogic_vector(XLEN-1 downto 0); -- alu result
  signal alu_add     : std_ulogic_vector(XLEN-1 downto 0); -- alu address result
  signal alu_cmp     : std_ulogic_vector(1 downto 0);      -- comparator result
  signal alu_cp_done : std_ulogic;                         -- alu co-processor operation done
  signal lsu_rdata   : std_ulogic_vector(XLEN-1 downto 0); -- lsu memory read data
  signal lsu_mar     : std_ulogic_vector(XLEN-1 downto 0); -- lsu memory address register
  signal lsu_err     : std_ulogic_vector(3 downto 0);      -- lsu alignment/access errors
  signal lsu_wait    : std_ulogic;                         -- wait for current data bus access
  signal dbus_req    : bus_req_t;                          -- data bus request
  signal csr_rdata   : std_ulogic_vector(XLEN-1 downto 0); -- csr read data
  signal pmp_fault   : std_ulogic;                         -- pmp permission violation
  signal irq_machine : std_ulogic_vector(2 downto 0);      -- risc-v standard machine-level interrupts

  -- [wbi] debug
  signal valid       : std_ulogic;                          -- bus signals are valid
  signal instr       : std_ulogic_vector(31 downto 0);      -- instruction

  -- Matrix Extension -----------------
  -------------------------------------

  -- mat mul engine state machine --
  type mat_mul_engine_state_t is (
    MM_RESET,
    MM_INIT_1, MM_PROCESS_1,
    MM_INIT_2, MM_PROCESS_2,
    MM_INIT_3, MM_PROCESS_3,
    MM_INIT_4, MM_PROCESS_4,
    MM_STORE,
    MM_DONE
  );
  signal mat_mul_engine_state : mat_mul_engine_state_t;

  signal matrix_ram_0 : ram_type;
  signal matrix_ram_1 : ram_type;
  signal matrix_ram_2 : ram_type;
  signal head : matrix_ram_addr;
  signal tail : matrix_ram_addr;
  signal transfer : std_ulogic;
  signal load : std_ulogic;
  signal store : std_ulogic;
  signal matrix_add : std_ulogic;
  signal matrix_mul : std_ulogic;
  signal matrix_operation_wait : std_ulogic;
  signal matrix_mar_load_store : std_ulogic_vector(XLEN-1 downto 0);
  signal data_out : std_ulogic_vector(XLEN-1 downto 0);
  signal data_in : std_ulogic_vector(XLEN-1 downto 0);
  signal matrix_immediate : std_ulogic_vector(XLEN-1 downto 0);

  signal c11 : unsigned(63 downto 0); -- := "0000000000000000000000000000000000000000000000000000000000000000";
  signal c12 : unsigned(63 downto 0);
  signal c13 : unsigned(63 downto 0);
  signal c14 : unsigned(63 downto 0);

  signal c21 : unsigned(63 downto 0);
  signal c22 : unsigned(63 downto 0);
  signal c23 : unsigned(63 downto 0);
  signal c24 : unsigned(63 downto 0);

  signal c31 : unsigned(63 downto 0);
  signal c32 : unsigned(63 downto 0);
  signal c33 : unsigned(63 downto 0);
  signal c34 : unsigned(63 downto 0);

  signal c41 : unsigned(63 downto 0);
  signal c42 : unsigned(63 downto 0);
  signal c43 : unsigned(63 downto 0);
  signal c44 : unsigned(63 downto 0);

  signal a11 : unsigned(31 downto 0);
  signal a21 : unsigned(31 downto 0);
  signal a31 : unsigned(31 downto 0);
  signal a41 : unsigned(31 downto 0);

  signal b11 : unsigned(31 downto 0);
  signal b12 : unsigned(31 downto 0);
  signal b13 : unsigned(31 downto 0);
  signal b14 : unsigned(31 downto 0);

begin

  -- Configuration Info and Checks --------------------------
  -- --------------------------------------------------------
  hello_neorv32:
  if HART_ID = 0 generate -- print only for core 0

    -- CPU ISA configuration (in alphabetical order - not in canonical order) --
    assert false report "[NEORV32] CPU ISA: rv32" &
      cond_sel_string_f(RISCV_ISA_E,      "e",         "i") &
      cond_sel_string_f(riscv_a_c,        "a",         "" ) &
      cond_sel_string_f(riscv_b_c,        "b",         "" ) &
      cond_sel_string_f(RISCV_ISA_C,      "c",         "" ) &
      cond_sel_string_f(RISCV_ISA_M,      "m",         "" ) &
      cond_sel_string_f(RISCV_ISA_U,      "u",         "" ) &
      cond_sel_string_f(true,             "x",         "" ) & -- always enabled
      cond_sel_string_f(RISCV_ISA_Zaamo,  "_zaamo",    "" ) &
      cond_sel_string_f(RISCV_ISA_Zalrsc, "_zalrsc",   "" ) &
      cond_sel_string_f(RISCV_ISA_C,      "_zca",      "" ) & -- Zcb requires Zca (=C) in the ISA string
      cond_sel_string_f(riscv_zcb_c,      "_zcb",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zba,    "_zba",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zbb,    "_zbb",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zbkb,   "_zbkb",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zbkc,   "_zbkc",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zbkx,   "_zbkx",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zbs,    "_zbs",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zibi,   "_zibi",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zicntr, "_zicntr",   "" ) &
      cond_sel_string_f(RISCV_ISA_Zicond, "_zicond",   "" ) &
      cond_sel_string_f(true,             "_zicsr",    "" ) & -- always enabled
      cond_sel_string_f(true,             "_zifencei", "" ) & -- always enabled
      cond_sel_string_f(RISCV_ISA_Zihpm,  "_zihpm",    "" ) &
      cond_sel_string_f(RISCV_ISA_Zfinx,  "_zfinx",    "" ) &
      cond_sel_string_f(riscv_zkn_c,      "_zkn",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zknd,   "_zknd",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zkne,   "_zkne",     "" ) &
      cond_sel_string_f(RISCV_ISA_Zknh,   "_zknh",     "" ) &
      cond_sel_string_f(riscv_zks_c,      "_zks",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zksed,  "_zksed",    "" ) &
      cond_sel_string_f(RISCV_ISA_Zksh,   "_zksh",     "" ) &
      cond_sel_string_f(riscv_zkt_c,      "_zkt",      "" ) &
      cond_sel_string_f(RISCV_ISA_Zmmul,  "_zmmul",    "" ) &
      cond_sel_string_f(RISCV_ISA_Zxcfu,  "_zxcfu",    "" ) &
      cond_sel_string_f(RISCV_ISA_Sdext,  "_sdext",    "" ) &
      cond_sel_string_f(RISCV_ISA_Sdtrig, "_sdtrig",   "" ) &
      cond_sel_string_f(RISCV_ISA_Smpmp,  "_smpmp",    "" )
      severity note;

    -- CPU tuning options --
    assert false report "[NEORV32] CPU tuning options: " &
      cond_sel_string_f(CPU_TRACE_EN,      "trace ",      "") &
      cond_sel_string_f(CPU_CONSTT_BR_EN,  "constt_br ",  "") &
      cond_sel_string_f(CPU_FAST_MUL_EN,   "fast_mul ",   "") &
      cond_sel_string_f(CPU_FAST_SHIFT_EN, "fast_shift ", "") &
      cond_sel_string_f(CPU_RF_HW_RST_EN,  "rf_hw_rst ",  "")
      severity note;

  end generate;


  -- Front-End (Instruction Fetch) --------------------------
  -- --------------------------------------------------------
  neorv32_cpu_frontend_inst: entity neorv32.neorv32_cpu_frontend
  generic map (
    RISCV_C   => RISCV_ISA_C,  -- implement C ISA extension
    RISCV_ZCB => RISCV_ISA_Zcb -- implement Zcb ISA sub-extension
  )
  port map (
    -- global control --
    clk_i      => clk_i,      -- global clock, rising edge
    rstn_i     => rstn_i,     -- global reset, low-active, async
    ctrl_i     => ctrl,       -- main control bus
    -- instruction fetch interface --
    ibus_req_o => ibus_req_o, -- request
    ibus_rsp_i => ibus_rsp_i, -- response
    -- back-end interface --
    frontend_o => frontend
  );



  PROC_MATRIX_MUL : process(clk_i, rstn_i)
    variable l : line;
  begin

    if (rstn_i = '0') then

      matrix_operation_wait <= '0';
      mat_mul_engine_state <= MM_RESET;

    elsif rising_edge(clk_i) then

      case mat_mul_engine_state is

        when MM_RESET =>

          transfer <= '0';

          if (matrix_mul = '1') then

            -- reset all registers to zero only when a new matrix mult starts so that
            -- the results of the old matrix mult is still available in the matrix engine
            -- in case the data needs to be stored back into CPU RAM

            c11 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c12 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c13 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c14 <= "0000000000000000000000000000000000000000000000000000000000000000";

            c21 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c22 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c23 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c24 <= "0000000000000000000000000000000000000000000000000000000000000000";

            c31 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c32 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c33 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c34 <= "0000000000000000000000000000000000000000000000000000000000000000";

            c41 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c42 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c43 <= "0000000000000000000000000000000000000000000000000000000000000000";
            c44 <= "0000000000000000000000000000000000000000000000000000000000000000";

            -- next state
            mat_mul_engine_state <= MM_INIT_1;

            -- make the execution engine wait in state EX_MATRIX_OPERATION_RSP
            matrix_operation_wait <= '1';

          end if;

        when MM_INIT_1 =>

          -- https://nandland.com/common-vhdl-conversions/#Numeric-Std_Logic_Vector-To-Unsigned

          a11 <= unsigned(matrix_ram_0(0));
          a21 <= unsigned(matrix_ram_0(4));
          a31 <= unsigned(matrix_ram_0(8));
          a41 <= unsigned(matrix_ram_0(12));

          b11 <= unsigned(matrix_ram_1(0));
          b12 <= unsigned(matrix_ram_1(1));
          b13 <= unsigned(matrix_ram_1(2));
          b14 <= unsigned(matrix_ram_1(3));

          -- next state
          mat_mul_engine_state <= MM_PROCESS_1;

        when MM_PROCESS_1 =>

          c11 <= c11 + (a11 * b11);
          c12 <= c12 + (a11 * b12);
          c13 <= c13 + (a11 * b13);
          c14 <= c14 + (a11 * b14);

          c21 <= c21 + (a21 * b11);
          c22 <= c22 + (a21 * b12);
          c23 <= c23 + (a21 * b13);
          c24 <= c24 + (a21 * b14);

          c31 <= c31 + (a31 * b11);
          c32 <= c32 + (a31 * b12);
          c33 <= c33 + (a31 * b13);
          c34 <= c34 + (a31 * b14);

          c41 <= c41 + (a41 * b11);
          c42 <= c42 + (a41 * b12);
          c43 <= c43 + (a41 * b13);
          c44 <= c44 + (a41 * b14);

          -- next state
          mat_mul_engine_state <= MM_INIT_2;

        when MM_INIT_2 =>

          a11 <= unsigned(matrix_ram_0(1));
          a21 <= unsigned(matrix_ram_0(5));
          a31 <= unsigned(matrix_ram_0(9));
          a41 <= unsigned(matrix_ram_0(13));

          b11 <= unsigned(matrix_ram_1(4));
          b12 <= unsigned(matrix_ram_1(5));
          b13 <= unsigned(matrix_ram_1(6));
          b14 <= unsigned(matrix_ram_1(7));

          -- next state
          mat_mul_engine_state <= MM_PROCESS_2;

        when MM_PROCESS_2 =>

          c11 <= c11 + (a11 * b11);
          c12 <= c12 + (a11 * b12);
          c13 <= c13 + (a11 * b13);
          c14 <= c14 + (a11 * b14);

          c21 <= c21 + (a21 * b11);
          c22 <= c22 + (a21 * b12);
          c23 <= c23 + (a21 * b13);
          c24 <= c24 + (a21 * b14);

          c31 <= c31 + (a31 * b11);
          c32 <= c32 + (a31 * b12);
          c33 <= c33 + (a31 * b13);
          c34 <= c34 + (a31 * b14);

          c41 <= c41 + (a41 * b11);
          c42 <= c42 + (a41 * b12);
          c43 <= c43 + (a41 * b13);
          c44 <= c44 + (a41 * b14);

          -- next state
          mat_mul_engine_state <= MM_INIT_3;

        when MM_INIT_3 =>

          a11 <= unsigned(matrix_ram_0(2));
          a21 <= unsigned(matrix_ram_0(6));
          a31 <= unsigned(matrix_ram_0(10));
          a41 <= unsigned(matrix_ram_0(14));

          b11 <= unsigned(matrix_ram_1(8));
          b12 <= unsigned(matrix_ram_1(9));
          b13 <= unsigned(matrix_ram_1(10));
          b14 <= unsigned(matrix_ram_1(11));

          -- next state
          mat_mul_engine_state <= MM_PROCESS_3;

        when MM_PROCESS_3 =>

          c11 <= c11 + (a11 * b11);
          c12 <= c12 + (a11 * b12);
          c13 <= c13 + (a11 * b13);
          c14 <= c14 + (a11 * b14);

          c21 <= c21 + (a21 * b11);
          c22 <= c22 + (a21 * b12);
          c23 <= c23 + (a21 * b13);
          c24 <= c24 + (a21 * b14);

          c31 <= c31 + (a31 * b11);
          c32 <= c32 + (a31 * b12);
          c33 <= c33 + (a31 * b13);
          c34 <= c34 + (a31 * b14);

          c41 <= c41 + (a41 * b11);
          c42 <= c42 + (a41 * b12);
          c43 <= c43 + (a41 * b13);
          c44 <= c44 + (a41 * b14);

          -- next state
          mat_mul_engine_state <= MM_INIT_4;

        when MM_INIT_4 =>

          a11 <= unsigned(matrix_ram_0(3));
          a21 <= unsigned(matrix_ram_0(7));
          a31 <= unsigned(matrix_ram_0(11));
          a41 <= unsigned(matrix_ram_0(15));

          b11 <= unsigned(matrix_ram_1(12));
          b12 <= unsigned(matrix_ram_1(13));
          b13 <= unsigned(matrix_ram_1(14));
          b14 <= unsigned(matrix_ram_1(15));

          -- next state
          mat_mul_engine_state <= MM_PROCESS_4;

        when MM_PROCESS_4 =>

          c11 <= c11 + (a11 * b11);
          c12 <= c12 + (a11 * b12);
          c13 <= c13 + (a11 * b13);
          c14 <= c14 + (a11 * b14);

          c21 <= c21 + (a21 * b11);
          c22 <= c22 + (a21 * b12);
          c23 <= c23 + (a21 * b13);
          c24 <= c24 + (a21 * b14);

          c31 <= c31 + (a31 * b11);
          c32 <= c32 + (a31 * b12);
          c33 <= c33 + (a31 * b13);
          c34 <= c34 + (a31 * b14);

          c41 <= c41 + (a41 * b11);
          c42 <= c42 + (a41 * b12);
          c43 <= c43 + (a41 * b13);
          c44 <= c44 + (a41 * b14);

          -- next state
          mat_mul_engine_state <= MM_STORE;

         when MM_STORE =>

            -- enable transfer in the RAM part
          transfer <= '1';

          -- next state
          mat_mul_engine_state <= MM_DONE;

        when MM_DONE =>

          transfer <= '0';

          -- all mult operations are done
          matrix_operation_wait <= '0';

          -- next state - this kills data before store!
          mat_mul_engine_state <= MM_RESET;

        when others => -- default

      end case;

    end if;

  end process PROC_MATRIX_MUL;




  -- https://vhdlwhiz.com/ring-buffer-fifo/
  PROC_RAM : process(clk_i)
    variable l : line;
  begin

    if (rstn_i = '0') then

    elsif rising_edge(clk_i) then

      if (transfer = '1') then

        -- store the c temporaries into the second matrix engine register
        matrix_ram_0(0) <= std_ulogic_vector(c11(31 downto 0));
        matrix_ram_0(1) <= std_ulogic_vector(c12(31 downto 0));
        matrix_ram_0(2) <= std_ulogic_vector(c13(31 downto 0));
        matrix_ram_0(3) <= std_ulogic_vector(c14(31 downto 0));

        matrix_ram_0(4) <= std_ulogic_vector(c21(31 downto 0));
        matrix_ram_0(5) <= std_ulogic_vector(c22(31 downto 0));
        matrix_ram_0(6) <= std_ulogic_vector(c23(31 downto 0));
        matrix_ram_0(7) <= std_ulogic_vector(c24(31 downto 0));

        matrix_ram_0(8) <= std_ulogic_vector(c31(31 downto 0));
        matrix_ram_0(9) <= std_ulogic_vector(c32(31 downto 0));
        matrix_ram_0(10) <= std_ulogic_vector(c33(31 downto 0));
        matrix_ram_0(11) <= std_ulogic_vector(c34(31 downto 0));

        matrix_ram_0(12) <= std_ulogic_vector(c41(31 downto 0));
        matrix_ram_0(13) <= std_ulogic_vector(c42(31 downto 0));
        matrix_ram_0(14) <= std_ulogic_vector(c43(31 downto 0));
        matrix_ram_0(15) <= std_ulogic_vector(c44(31 downto 0));




        -- store the c temporaries into the second matrix engine register
        matrix_ram_1(0) <= std_ulogic_vector(c11(31 downto 0));
        matrix_ram_1(1) <= std_ulogic_vector(c12(31 downto 0));
        matrix_ram_1(2) <= std_ulogic_vector(c13(31 downto 0));
        matrix_ram_1(3) <= std_ulogic_vector(c14(31 downto 0));

        matrix_ram_1(4) <= std_ulogic_vector(c21(31 downto 0));
        matrix_ram_1(5) <= std_ulogic_vector(c22(31 downto 0));
        matrix_ram_1(6) <= std_ulogic_vector(c23(31 downto 0));
        matrix_ram_1(7) <= std_ulogic_vector(c24(31 downto 0));

        matrix_ram_1(8) <= std_ulogic_vector(c31(31 downto 0));
        matrix_ram_1(9) <= std_ulogic_vector(c32(31 downto 0));
        matrix_ram_1(10) <= std_ulogic_vector(c33(31 downto 0));
        matrix_ram_1(11) <= std_ulogic_vector(c34(31 downto 0));

        matrix_ram_1(12) <= std_ulogic_vector(c41(31 downto 0));
        matrix_ram_1(13) <= std_ulogic_vector(c42(31 downto 0));
        matrix_ram_1(14) <= std_ulogic_vector(c43(31 downto 0));
        matrix_ram_1(15) <= std_ulogic_vector(c44(31 downto 0));

      end if;

      if (load = '1') then

        -- data_out is the output of the LoadStoreUnit (LSU) and it contains the RAM/cache value
        -- which is loaded into the MatrixEngine
        if (to_integer(unsigned(matrix_immediate)) = 0) then
          matrix_ram_0(head) <= data_out;
        else
          matrix_ram_1(head) <= data_out;
        end if;

      end if;

      if (store = '1') then

        if (to_integer(unsigned(matrix_immediate)) = 0) then
          data_in <= matrix_ram_0(tail);
        else
          data_in <= matrix_ram_1(tail);
        end if;

      end if;

      if (matrix_add = '1') then

        for i in 0 to 15 loop
          matrix_ram_0(i) <= std_ulogic_vector(unsigned(matrix_ram_0(i)) + unsigned(matrix_immediate));
        end loop;

      end if;

    end if;
  end process PROC_RAM;




  -- Control Unit (Back-End / Instruction Execution) --------
  -- --------------------------------------------------------
  neorv32_cpu_control_inst: entity neorv32.neorv32_cpu_control
  generic map (
    -- General --
    HART_ID           => HART_ID,           -- hardware thread ID
    BOOT_ADDR         => BOOT_ADDR,         -- cpu boot address
    DEBUG_PARK_ADDR   => DEBUG_PARK_ADDR,   -- cpu debug mode parking loop entry address
    DEBUG_EXC_ADDR    => DEBUG_EXC_ADDR,    -- cpu debug mode exception entry address
    -- RISC-V ISA Extensions --
    RISCV_ISA_A       => riscv_a_c,         -- atomic memory operations extension
    RISCV_ISA_B       => riscv_b_c,         -- bit-manipulation extension
    RISCV_ISA_C       => RISCV_ISA_C,       -- compressed extension
    RISCV_ISA_E       => RISCV_ISA_E,       -- embedded RF extension
    RISCV_ISA_M       => RISCV_ISA_M,       -- mul/div extension
    RISCV_ISA_U       => RISCV_ISA_U,       -- user mode extension
    RISCV_ISA_Zaamo   => RISCV_ISA_Zaamo,   -- atomic read-modify-write operations extension
    RISCV_ISA_Zalrsc  => RISCV_ISA_Zalrsc,  -- atomic reservation-set operations extension
    RISCV_ISA_Zcb     => riscv_zcb_c,       -- additional code size reduction instructions
    RISCV_ISA_Zba     => RISCV_ISA_Zba,     -- shifted-add bit-manipulation extension
    RISCV_ISA_Zbb     => RISCV_ISA_Zbb,     -- basic bit-manipulation extension
    RISCV_ISA_Zbkb    => RISCV_ISA_Zbkb,    -- bit-manipulation instructions for cryptography
    RISCV_ISA_Zbkc    => RISCV_ISA_Zbkc,    -- carry-less multiplication instructions
    RISCV_ISA_Zbkx    => RISCV_ISA_Zbkx,    -- cryptography crossbar permutation extension
    RISCV_ISA_Zbs     => RISCV_ISA_Zbs,     -- single-bit bit-manipulation extension
    RISCV_ISA_Zfinx   => RISCV_ISA_Zfinx,   -- 32-bit floating-point extension
    RISCV_ISA_Zibi    => RISCV_ISA_Zibi,    -- branch with immediate
    RISCV_ISA_Zicntr  => RISCV_ISA_Zicntr,  -- base counters
    RISCV_ISA_Zicond  => RISCV_ISA_Zicond,  -- integer conditional operations
    RISCV_ISA_Zihpm   => RISCV_ISA_Zihpm,   -- hardware performance monitors
    RISCV_ISA_Zkn     => riscv_zkn_c,       -- NIST algorithm suite available
    RISCV_ISA_Zknd    => RISCV_ISA_Zknd,    -- cryptography NIST AES decryption extension
    RISCV_ISA_Zkne    => RISCV_ISA_Zkne,    -- cryptography NIST AES encryption extension
    RISCV_ISA_Zknh    => RISCV_ISA_Zknh,    -- cryptography NIST hash extension
    RISCV_ISA_Zks     => riscv_zks_c,       -- ShangMi algorithm suite available
    RISCV_ISA_Zksed   => RISCV_ISA_Zksed,   -- ShangMi block cipher extension
    RISCV_ISA_Zksh    => RISCV_ISA_Zksh,    -- ShangMi hash extension
    RISCV_ISA_Zkt     => riscv_zkt_c,       -- data-independent execution time for cryptography operations available
    RISCV_ISA_Zmmul   => RISCV_ISA_Zmmul,   -- multiply-only M sub-extension
    RISCV_ISA_Zxcfu   => RISCV_ISA_Zxcfu,   -- custom (instr.) functions unit
    RISCV_ISA_Sdext   => RISCV_ISA_Sdext,   -- external debug mode extension
    RISCV_ISA_Sdtrig  => RISCV_ISA_Sdtrig,  -- trigger module extension
    RISCV_ISA_Smpmp   => RISCV_ISA_Smpmp,   -- physical memory protection
    -- Tuning Options --
    CPU_TRACE_EN      => CPU_TRACE_EN,      -- enable CPU execution trace generator
    CPU_CONSTT_BR_EN  => CPU_CONSTT_BR_EN,  -- constant-time branches
    CPU_FAST_MUL_EN   => CPU_FAST_MUL_EN,   -- use DSPs for M extension's multiplier
    CPU_FAST_SHIFT_EN => CPU_FAST_SHIFT_EN, -- use barrel shifter for shift operations
    CPU_RF_HW_RST_EN  => CPU_RF_HW_RST_EN   -- enable full hardware reset for register file
  )
  port map (
    -- global control --
    clk_i         => clk_i,           -- global clock, rising edge
    rstn_i        => rstn_i,          -- global reset, low-active, async
    ctrl_o        => ctrl,            -- main control bus
    -- misc --
    frontend_i    => frontend,        -- front-end status and data
    pmp_fault_i   => pmp_fault,       -- instruction fetch / execute pmp fault
    hwtrig_i      => hwtrig,          -- hardware trigger
    -- [debug] - make instruction visible
    debug_valid_i => frontend.valid,  -- bus signals are valid
    debug_instr_i => frontend.instr,  -- instruction
    -- matrix extension
    matrix_add_o              => matrix_add,
    matrix_mul_o              => matrix_mul,
    matrix_immediate_o        => matrix_immediate,
    matrix_mar_load_store_o   => matrix_mar_load_store,
    matrix_operation_wait_i   => matrix_operation_wait, -- make the execution engine wait for the matrix engine
    -- data path interface --
    alu_cp_done_i => alu_cp_done, -- ALU iterative operation done
    alu_cmp_i     => alu_cmp,     -- comparator status
    alu_add_i     => alu_add,     -- ALU address result
    rf_rs1_i      => rs1,         -- rf source 1
    csr_rdata_o   => csr_rdata,   -- CSR read data
    xcsr_rdata_i  => xcsr_res,    -- external CSR read data
    -- interrupts --
    irq_dbg_i     => dbi_i,       -- debug mode (halt) request
    irq_machine_i => irq_machine, -- risc-v mei, mti, msi
    irq_fast_i    => firq_i,      -- fast interrupts
    -- from/to load/store unit interface --
    lsu_wait_i    => lsu_wait,    -- make the execution engine wait for data bus
    lsu_mar_i     => lsu_mar,     -- memory address register
    lsu_err_i     => lsu_err      -- alignment/access errors
  );

  -- RISC-V machine interrupts --
  irq_machine <= mei_i & mti_i & msi_i;

  -- control-external CSR read-back --
  xcsr_res <= xcsr_tm or xcsr_cnt or xcsr_alu or xcsr_pmp;

  -- CPU is sleeping --
  sleep_o <= not ctrl.cnt_event(cnt_event_cy_c);


  -- Hardware Trigger Module (Sdtrig) -----------------------
  -- --------------------------------------------------------
  trigger_module_enabled:
  if (RISCV_ISA_Sdtrig = true) and (NUM_HW_TRIGGERS > 0) generate
    neorv32_cpu_hwtrig_inst: entity neorv32.neorv32_cpu_hwtrig
    generic map (
      NUM_TRIGGERS => NUM_HW_TRIGGERS, -- number of implemented hardware triggers
      RISCV_ISA_U  => RISCV_ISA_U      -- RISC-V user-mode available
    )
    port map (
    -- global control --
      clk_i  => clk_i,   -- global clock, rising edge
      rstn_i => rstn_i,  -- global reset, low-active, async
      ctrl_i => ctrl,    -- main control bus
      -- data path --
      mar_i  => lsu_mar, -- memory address register
      csr_o  => xcsr_tm, -- CSR read data
      -- trigger firing --
      hit_o  => hwtrig   -- high until debug-mode is entered
    );
  end generate;

  trigger_module_disabled:
  if (RISCV_ISA_Sdtrig = false) or (NUM_HW_TRIGGERS = 0) generate
    xcsr_tm <= (others => '0');
    hwtrig  <= '0';
  end generate;


  -- Hardware Counters --------------------------------------
  -- --------------------------------------------------------
  cnts_enabled:
  if RISCV_ISA_Zicntr or RISCV_ISA_Zihpm generate
    neorv32_cpu_counters_inst: entity neorv32.neorv32_cpu_counters
    generic map (
    ZICNTR_EN => RISCV_ISA_Zicntr, -- implement base counters
    ZIHPM_EN  => RISCV_ISA_Zihpm,  -- implement hardware performance monitors (HPMs)
    HPM_NUM   => HPM_NUM_CNTS,     -- number of implemented HPM counters (0..13)
    HPM_WIDTH => HPM_CNT_WIDTH     -- total size of HPM counters (0..64)
    )
    port map (
      -- global control --
      clk_i   => clk_i,   -- global clock, rising edge
      rstn_i  => rstn_i,  -- global reset, low-active, async
      ctrl_i  => ctrl,    -- main control bus
      -- read back --
      rdata_o => xcsr_cnt -- read data
    );
  end generate;

  cnts_disabled:
  if (not RISCV_ISA_Zicntr) and (not RISCV_ISA_Zihpm) generate
    xcsr_cnt <= (others => '0');
  end generate;


  -- X Register File (Normal RV32) --------------------------
  -- --------------------------------------------------------
  neorv32_cpu_regfile_inst: entity neorv32.neorv32_cpu_regfile
  generic map (
    RST_EN => CPU_RF_HW_RST_EN, -- enable dedicated hardware reset ("ASIC style")
    RVE_EN => RISCV_ISA_E       -- implement embedded RF extension
  )
  port map (
    -- global control --
    clk_i  => clk_i,    -- global clock, rising edge
    rstn_i => rstn_i,   -- global reset, low-active, async
    ctrl_i => ctrl,     -- main control bus
    -- operands --
    rd_i   => rf_wdata, -- destination operand rd
    rs1_o  => rs1,      -- source operand rs1
    rs2_o  => rs2       -- source operand rs2
  );

  -- signal into the x register file (normal RV32)
  -- all buses are zero unless there is an according operation --
  rf_wdata <= alu_res or lsu_rdata or csr_rdata or ctrl.pc_ret;

  -- M Register File (Normal RV32) --------------------------
  -- --------------------------------------------------------
  neorv32_cpu_m_regfile_inst: entity neorv32.neorv32_m_cpu_regfile
  generic map (
    RST_EN => CPU_RF_HW_RST_EN, -- enable dedicated hardware reset ("ASIC style")
    RVE_EN => RISCV_ISA_E       -- implement embedded RF extension
  )
  port map (
    -- global control --
    clk_i  => clk_i,    -- global clock, rising edge
    rstn_i => rstn_i,   -- global reset, low-active, async
    ctrl_i => ctrl,     -- main control bus
    -- operands --
    rd_i   => m_rf_wdata --, -- destination operand rd
  );

  -- signal into the m register file (matrix extension)
  -- all buses are zero unless there is an according operation --
  m_rf_wdata <= lsu_rdata;


  -- Arithmetic/Logic Unit (ALU) and ALU Co-Processors ------
  -- --------------------------------------------------------
  neorv32_cpu_alu_inst: entity neorv32.neorv32_cpu_alu
  generic map (
    -- RISC-V CPU Extensions --
    RISCV_ISA_M      => RISCV_ISA_M,      -- mul/div extension
    RISCV_ISA_Zba    => RISCV_ISA_Zba,    -- address-generation instruction
    RISCV_ISA_Zbb    => RISCV_ISA_Zbb,    -- basic bit-manipulation instruction
    RISCV_ISA_Zbkb   => RISCV_ISA_Zbkb,   -- bit-manipulation instructions for cryptography
    RISCV_ISA_Zbkc   => RISCV_ISA_Zbkc,   -- carry-less multiplication instructions
    RISCV_ISA_Zbkx   => RISCV_ISA_Zbkx,   -- cryptography crossbar permutation extension
    RISCV_ISA_Zbs    => RISCV_ISA_Zbs,    -- single-bit instructions
    RISCV_ISA_Zfinx  => RISCV_ISA_Zfinx,  -- 32-bit floating-point extension
    RISCV_ISA_Zibi   => RISCV_ISA_Zibi,   -- branch with immediate
    RISCV_ISA_Zicond => RISCV_ISA_Zicond, -- integer conditional operations
    RISCV_ISA_Zknd   => RISCV_ISA_Zknd,   -- cryptography NIST AES decryption extension
    RISCV_ISA_Zkne   => RISCV_ISA_Zkne,   -- cryptography NIST AES encryption extension
    RISCV_ISA_Zknh   => RISCV_ISA_Zknh,   -- cryptography NIST hash extension
    RISCV_ISA_Zksed  => RISCV_ISA_Zksed,  -- ShangMi block cipher extension
    RISCV_ISA_Zksh   => RISCV_ISA_Zksh,   -- ShangMi hash extension
    RISCV_ISA_Zmmul  => RISCV_ISA_Zmmul,  -- multiply-only M sub-extension
    RISCV_ISA_Zxcfu  => RISCV_ISA_Zxcfu,  -- custom (instr.) functions unit
    -- Tuning Options --
    FAST_MUL_EN      => CPU_FAST_MUL_EN,  -- use DSPs for M extension's multiplier
    FAST_SHIFT_EN    => CPU_FAST_SHIFT_EN -- use barrel shifter for shift operations
  )
  port map (
    -- global control --
    clk_i  => clk_i,      -- global clock, rising edge
    rstn_i => rstn_i,     -- global reset, low-active, async
    ctrl_i => ctrl,       -- main control bus
    -- [debug] --
    debug_alu_op => ctrl.alu_op,
    -- data input --
    rs1_i  => rs1,        -- rf source 1
    rs2_i  => rs2,        -- rf source 2
    -- data output --
    cmp_o  => alu_cmp,    -- comparator status
    res_o  => alu_res,    -- ALU result
    add_o  => alu_add,    -- address computation result
    csr_o  => xcsr_alu,   -- CSR read data
    -- status --
    done_o => alu_cp_done -- iterative processing units done?
  );


  -- -- Load/Store Unit (LSU) -------------------------------
  -- -- -----------------------------------------------------

  neorv32_cpu_m_lsu_inst: entity neorv32.neorv32_cpu_m_lsu
  port map (
    -- global control --
    clk_i       => clk_i,     -- global clock, rising edge
    rstn_i      => rstn_i,    -- global reset, low-active, async
    ctrl_i      => ctrl,      -- main control bus
    -- debug
    lsu_req_i   => ctrl.lsu_req,
    lsu_en_i    => ctrl.lsu_m_en,
    -- matrix extension
    head_o      => head,
    tail_o      => tail,
    load_o      => load,
    store_o     => store,
    data_out_o  => data_out, -- data_out is from CPU RAM to Matrix RAM
    data_in_i   => data_in, -- data_out is from Matrix RAM to CPU RAM
    matrix_immediate_i => matrix_immediate, -- immediate value from the
    matrix_mar_load_store_i => matrix_mar_load_store, -- memory address
    -- cpu data access interface --
    addr_i      => alu_add,   -- access address
    wdata_i     => rs2,       -- write data
    rdata_o     => lsu_rdata, -- read data
    mar_o       => lsu_mar,   -- memory address register
    wait_o      => lsu_wait,  -- wait for access to complete -- this signal tells the execution engine to wait for the load/store to complete before advancing
    err_o       => lsu_err,   -- alignment/access errors
    pmp_fault_i => pmp_fault, -- PMP read/write access fault
    -- data bus --
    dbus_req_o  => dbus_req,  -- request
    dbus_rsp_i  => dbus_rsp_i, -- response
    -- debug
    dbus_rsp_i_ack => dbus_rsp_i.ack
  );

  dbus_req_o <= dbus_req;


  -- Physical Memory Protection (PMP) -----------------------
  -- --------------------------------------------------------
  pmp_enabled:
  if RISCV_ISA_Smpmp generate
    neorv32_cpu_pmp_inst: entity neorv32.neorv32_cpu_pmp
    generic map (
      NUM_REGIONS => PMP_NUM_REGIONS,     -- number of regions (0..16)
      GRANULARITY => PMP_MIN_GRANULARITY, -- minimal region granularity in bytes, has to be a power of 2, min 4 bytes
      TOR_EN      => PMP_TOR_MODE_EN,     -- enable TOR mode
      NAP_EN      => PMP_NAP_MODE_EN      -- enable NAPOT/NA4 modes
    )
    port map (
      -- global control --
      clk_i   => clk_i,    -- global clock, rising edge
      rstn_i  => rstn_i,   -- global reset, low-active, async
      ctrl_i  => ctrl,     -- main control bus
      -- operands --
      csr_o   => xcsr_pmp, -- CSR read data
      rs1_i   => rs1,      -- data access base address
      -- access error --
      fault_o => pmp_fault -- permission violation
    );
  end generate;

  pmp_disabled:
  if not RISCV_ISA_Smpmp generate
    xcsr_pmp  <= (others => '0');
    pmp_fault <= '0';
  end generate;


  -- Trace Generator ----------------------------------------
  -- --------------------------------------------------------
  trace_enabled:
  if CPU_TRACE_EN generate
    neorv32_cpu_trace_inst: entity neorv32.neorv32_cpu_trace
    port map (
      -- global control --
      clk_i       => clk_i,         -- global clock, rising edge
      rstn_i      => rstn_i,        -- global reset, low-active, async
      ctrl_i      => ctrl,          -- main control bus
      -- operands --
      rs1_rdata_i => rs1,           -- rs1 read data
      rs2_rdata_i => rs2,           -- rs2 read data
      rd_wdata_i  => rf_wdata,      -- rd write data
      mem_ben_i   => dbus_req.ben,  -- memory byte-enable
      mem_addr_i  => dbus_req.addr, -- memory address
      mem_wdata_i => dbus_req.data, -- memory write data
      -- trace port --
      trace_o     => trace_o        -- execution trace port
    );
  end generate;

  trace_disabled:
  if not CPU_TRACE_EN generate
    trace_o <= trace_port_terminate_c;
  end generate;


end neorv32_cpu_rtl;
