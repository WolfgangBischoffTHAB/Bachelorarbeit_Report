-- ================================================================================ --
-- NEORV32 CPU - Load/Store Unit                                                    --
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

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu_m_lsu is
  port (
    -- global control --
    clk_i       : in  std_ulogic; -- global clock, rising edge
    rstn_i      : in  std_ulogic; -- global reset, low-active, async
    ctrl_i      : in  ctrl_bus_t; -- main control bus
    -- debug
    lsu_req_i   : in  std_ulogic;
    lsu_en_i    : in  std_ulogic; -- matrix enable
    -- matrix extension
    head_o      : inout matrix_ram_addr;
    tail_o      : inout matrix_ram_addr;
    load_o      : out std_ulogic;
    store_o     : out std_ulogic;
    data_out_o  : out std_ulogic_vector(31 downto 0); -- data_out is from CPU RAM to Matrix RAM
    data_in_i   : in std_ulogic_vector(31 downto 0); -- data_out is from Matrix RAM to CPU RAM
    matrix_immediate_i : in std_ulogic_vector(XLEN-1 downto 0);
    matrix_mar_load_store_i : in std_ulogic_vector(XLEN-1 downto 0);
    -- cpu data access interface --
    addr_i      : in  std_ulogic_vector(XLEN-1 downto 0); -- access address
    wdata_i     : in  std_ulogic_vector(XLEN-1 downto 0); -- write data
    rdata_o     : out std_ulogic_vector(XLEN-1 downto 0); -- read data
    mar_o       : out std_ulogic_vector(XLEN-1 downto 0); -- current memory address register
    wait_o      : out std_ulogic; -- wait for access to complete
    err_o       : out std_ulogic_vector(3 downto 0); -- alignment/access errors
    pmp_fault_i : in  std_ulogic; -- PMP read/write access fault
    -- data bus --
    dbus_req_o  : out bus_req_t; -- request
    dbus_rsp_i  : in  bus_rsp_t; -- response, in neorv32_cpu.vhd:l.579 this signal is connected to a port of the neorv32_cpu. Then in neorv32_top.vhd this port is connected to neorv32_dcache_inst.host_rsp_o => cpu_d_rsp(i),
    -- debug
    dbus_rsp_i_ack : in std_ulogic
--    debug_data_output : out std_ulogic_vector(31 downto 0)

--    meta_o  : out std_ulogic_vector(2 downto 0);
--    addr_o  : out std_ulogic_vector(31 downto 0);
--    data_o  : out std_ulogic_vector(31 downto 0);
--    ben_o   : out std_ulogic_vector(3 downto 0);
--    stb_o   : out std_ulogic;
--    rw_o    : out std_ulogic;
--    amo_o   : out std_ulogic;
--    amoop_o : out std_ulogic_vector(3 downto 0);
--    burst_o : out std_ulogic;
--    lock_o  : out std_ulogic;
--    fence_o : out std_ulogic
  );
end neorv32_cpu_m_lsu;


architecture neorv32_cpu_lsu_rtl of neorv32_cpu_m_lsu is

  signal mar        : std_ulogic_vector(XLEN-1 downto 0); -- memory address register
  signal misaligned : std_ulogic; -- misaligned address
  signal pending    : std_ulogic; -- pending bus request
  signal pmp_err    : std_ulogic; -- PMP access violation
  signal amo_cmd    : std_ulogic_vector(3 downto 0); -- atomic memory operation type
  signal exc_rd     : std_ulogic; -- for exceptions: this is a read operation
  signal exc_wr     : std_ulogic; -- for exceptions: this is a write operation

  signal matrix_wait_for_load_finished : std_ulogic;
  signal matrix_wait_for_store_finished : std_ulogic;

  signal matrix_stb_counter_load : integer; -- for loading data from CPU RAM into the matrix engine
  signal matrix_stb_counter_store : integer; -- for loading data from the matrix engine into CPU RAM
  signal matrix_stb : std_ulogic;
  signal matrix_mar_store : std_ulogic_vector(XLEN-1 downto 0);
  signal matrix_mar_load : std_ulogic_vector(XLEN-1 downto 0);

  signal matrix_reg_file : my_array_t(MLEN-1 downto 0, MLEN-1 downto 0);

  signal test : YOUR_ARRAY_TYPE;

  signal rd_data : std_ulogic_vector(31 downto 0);

  signal load : std_ulogic; -- LSU currently performs a matrix LOAD operation
  signal store : std_ulogic; -- LSU currently performs a matrix STORE operation

  signal seen_001 : std_ulogic;

  type matrix_load_state_t is ( ML_IDLE, ML_INIT, ML_PROCESS, ML_INCREMENT );
  signal matrix_load_state : matrix_load_state_t;

  type matrix_store_state_t is (
    MS_IDLE,
    MS_INIT,
    MS_PROCESS,
    MS_INCREMENT,
    MS_WAIT_FOR_STORE_DATA_1,
    MS_WAIT_FOR_STORE_DATA_2,
    MS_WAIT_FOR_STORE_DATA_3,
    MS_WAIT_FOR_STORE_DATA_4
  );
  signal matrix_store_state : matrix_store_state_t;

begin

--  meta_o <= dbus_req_o.meta;
--  addr_o <= dbus_req_o.addr;
--  data_o <= dbus_req_o.data;
--  ben_o <= dbus_req_o.ben;
--  stb_o <= dbus_req_o.stb;
--  rw_o <= dbus_req_o.rw;
--  amo_o <= dbus_req_o.amo;
--  amoop_o <= dbus_req_o.amoop;
--  burst_o <= dbus_req_o.burst;
--  lock_o <= dbus_req_o.lock;
--  fence_o <= dbus_req_o.fence;

  -- Access Address -------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  mem_addr_reg: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      mar        <= (others => '0');
      misaligned <= '0';
    elsif rising_edge(clk_i) then
      if (ctrl_i.lsu_mo_we = '1') then
        mar <= addr_i; -- memory address register
        misaligned <= '0';
        -- case ctrl_i.ir_funct3(1 downto 0) is -- alignment check
        --   when "00"   => misaligned <= '0'; -- byte
        --   when "01"   => misaligned <= addr_i(0); -- half-word
        --   when others => misaligned <= addr_i(1) or addr_i(0); -- word
        -- end case;
      end if;
    end if;
  end process mem_addr_reg;

  STROBE_PROCESS : process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      matrix_stb <= '0';
    else

      matrix_stb <= ctrl_i.lsu_m_en;

      -- if (ctrl_i.lsu_m_en = '1') then
      --   -- create a strobe command for the memory bus request
      --   if matrix_stb <= '0' then
      --     matrix_stb <= '1';
      --   else
      --     matrix_stb <= '0';
      --   end if;
      -- end if;

    end if;
  end process STROBE_PROCESS;


  -- Data Output: Alignment, Byte Enable and Type Identifiers -------------------------------
  -- Maybe this part is for output towards RAM for store operations such as SB, SH, SW and SD
  -- ----------------------------------------------------------------------------------------
  mem_do_reg: process(rstn_i, clk_i)
     variable l : line;
  begin

    if (rstn_i = '0') then

      dbus_req_o.meta  <= (others => '0');
      dbus_req_o.amo   <= '0';
      dbus_req_o.amoop <= (others => '0');
      dbus_req_o.data  <= (others => '0');
      dbus_req_o.ben   <= (others => '0');

      tail_o <= 0;

      matrix_stb_counter_store <= 0;

      matrix_wait_for_store_finished <= '0';

      matrix_mar_store <= matrix_mar_load_store_i;

      --matrix_store_state <= MS_INIT;

      -- DEBUG
      --  write(l, String'("LSU STORE RESET"));
      --  writeline(output, l);

    elsif rising_edge(clk_i) then

      -- -- DEBUG
      -- write(l, String'("Store"));
      -- writeline(output, l);
      -- write(l, ctrl_i.lsu_m_en);
      -- writeline(output, l);

      if (ctrl_i.lsu_m_en = '0') then -- if NO matrix load command is executed, perform normal sb, sh, sw

        -- lsu_mo_we == write memory output registers (data & address)
        if (ctrl_i.lsu_mo_we = '1') then

          -- access identifiers --
          dbus_req_o.meta  <= ctrl_i.cpu_debug & ctrl_i.lsu_priv & '0'; -- LSB: data access
          dbus_req_o.rw    <= ctrl_i.lsu_rw; -- read/write
          dbus_req_o.amo   <= ctrl_i.lsu_rmw or ctrl_i.lsu_rvs; -- atomic memory operation
          dbus_req_o.amoop <= amo_cmd;

          -- data alignment + byte-enable --
          case ctrl_i.ir_funct3(1 downto 0) is
            when "00" => -- byte
              dbus_req_o.data   <= wdata_i(7 downto 0) & wdata_i(7 downto 0) & wdata_i(7 downto 0) & wdata_i(7 downto 0);
              dbus_req_o.ben(0) <= (not addr_i(1)) and (not addr_i(0));
              dbus_req_o.ben(1) <= (not addr_i(1)) and (    addr_i(0));
              dbus_req_o.ben(2) <= (    addr_i(1)) and (not addr_i(0));
              dbus_req_o.ben(3) <= (    addr_i(1)) and (    addr_i(0));
            when "01" => -- half-word
              dbus_req_o.data <= wdata_i(15 downto 0) & wdata_i(15 downto 0);
              dbus_req_o.ben  <= addr_i(1) & addr_i(1) & (not addr_i(1)) & (not addr_i(1));
            when others => -- word
              dbus_req_o.data <= wdata_i;
              dbus_req_o.ben  <= (others => '1');
          end case;

        end if;

        -- MS_IDLE, MS_INIT, MS_PROCESS, MS_INCREMENT
        matrix_store_state <= MS_INIT;

        --matrix_wait_for_store_finished <= '0';
        matrix_stb_counter_store <= 0;
        tail_o <= 0;

      elsif (ctrl_i.ir_funct3(2 downto 0) = "001") then -- Matrix store

        case matrix_store_state is

          when MS_IDLE => -- nop

            -- -- DEBUG
            -- write(l, String'("LSU MATRIX STORE MS_IDLE"));
            -- writeline(output, l);

            store <= '0';

          when MS_INIT =>

            -- DEBUG
            --write(l, String'("LSU MATRIX STORE MS_INIT"));
            --writeline(output, l);

            -- set address into Memory Address Register
            matrix_mar_store <= matrix_mar_load_store_i;

            -- set values
            matrix_stb_counter_store <= 0;
            matrix_wait_for_store_finished <= '1';
            store <= '1';
            tail_o <= 0;

            -- next state
            matrix_store_state <= MS_WAIT_FOR_STORE_DATA_1;

          when MS_WAIT_FOR_STORE_DATA_1 =>

            -- next state
            matrix_store_state <= MS_WAIT_FOR_STORE_DATA_2;

          when MS_WAIT_FOR_STORE_DATA_2 =>

            -- next state
            matrix_store_state <= MS_WAIT_FOR_STORE_DATA_3;

          when MS_WAIT_FOR_STORE_DATA_3 =>

            -- next state
            matrix_store_state <= MS_WAIT_FOR_STORE_DATA_4;

          when MS_WAIT_FOR_STORE_DATA_4 =>

            -- next state
            matrix_store_state <= MS_PROCESS;

          when MS_PROCESS =>

            -- -- DEBUG
            -- write(l, String'("LSU MATRIX STORE MS_PROCESS"));
            -- writeline(output, l);

            -- -- DEBUG asdf
            -- write(l, data_in_i);
            -- writeline(output, l);

            -- if (dbus_rsp_i.ack = '0')

            -- -- lsu_mo_we == write memory output registers (data & address)
            -- if (ctrl_i.lsu_mo_we = '1') then

            --   -- access identifiers --
            --   dbus_req_o.meta  <= ctrl_i.cpu_debug & ctrl_i.lsu_priv & '0'; -- LSB: data access
            --   dbus_req_o.rw    <= ctrl_i.lsu_rw; -- read/write
            --   dbus_req_o.amo   <= ctrl_i.lsu_rmw or ctrl_i.lsu_rvs; -- atomic memory operation
            --   dbus_req_o.amoop <= amo_cmd;

            --   -- word
            --   --dbus_req_o.data <= rd_data;
            --dbus_req_o.data <= x"000000FF";
            --dbus_req_o.ben  <= (others => '1');

            -- end if;

            -- need to wait for the cache and the memory to respond before advancing in the state machine
            if (dbus_rsp_i.ack = '1') then

              if (tail_o < 15) then

                -- -- DEBUG
                -- write(l, String'("LSU MATRIX STORE TAIL<15"));
                -- writeline(output, l);

                -- -- DEBUG
                -- --write(l, data_in_i);
                -- write(l, to_hstring(unsigned(data_in_i)));
                -- writeline(output, l);

                dbus_req_o.rw <= '1';
                dbus_req_o.data <= data_in_i;
                dbus_req_o.ben  <= (others => '1');

                matrix_store_state <= MS_INCREMENT;

                -- keep track of outstanding elements to strobe
                matrix_stb_counter_store <= matrix_stb_counter_store + 1;

              else

                matrix_wait_for_store_finished <= '0'; -- done waiting
                matrix_store_state <= MS_IDLE; -- GOTO IDLE state and remain until next activation of the MATRIX LSU

              end if;

              -- -- debug
              -- write(l, "LSU STORE: 0x" & to_hstring(unsigned(matrix_mar_store)));
              -- writeline(output, l);

            end if;

          when MS_INCREMENT =>

            -- advance address (aka. pointer)
            matrix_mar_store <= std_ulogic_vector(unsigned(matrix_mar_store) + 4);

            -- -- DEBUG
            -- write(l, String'("LSU MATRIX STORE MS_INCREMENT"));
            -- writeline(output, l);

            tail_o <= tail_o + 1;
            matrix_store_state <= MS_PROCESS;

          when others =>

            -- DEBUG
            --write(l, String'("LSU STORE others"));
            --writeline(output, l);

        end case;

      end if;

    end if;

  end process mem_do_reg;


  -- hardwired signals --
  dbus_req_o.burst <= '0'; -- only single-access

  -- out-of-band signals --
  dbus_req_o.fence <= ctrl_i.lsu_fence;

  -- atomic memory access operation encoding --
  amo_encode: process(ctrl_i.ir_funct12)
  begin
    case ctrl_i.ir_funct12(11 downto 7) is
      when "00010" => amo_cmd <= "1000"; -- Zalrsc.LR
      when "00011" => amo_cmd <= "1001"; -- Zalrsc.SC
      when "00000" => amo_cmd <= "0001"; -- Zaamo.ADD
      when "00100" => amo_cmd <= "0010"; -- Zaamo.XOR
      when "01100" => amo_cmd <= "0011"; -- Zaamo.AND
      when "01000" => amo_cmd <= "0100"; -- Zaamo.OR
      when "10000" => amo_cmd <= "1110"; -- Zaamo.MIN
      when "10100" => amo_cmd <= "1111"; -- Zaamo.MAX
      when "11000" => amo_cmd <= "0110"; -- Zaamo.MINU
      when "11100" => amo_cmd <= "0111"; -- Zaamo.MAXU
      when others  => amo_cmd <= "0000"; -- Zaamo.SWAP
    end case;
  end process;


  -- Bus-Locking (for atomic read-modify-write operations) ----------------------------------
  -- -------------------------------------------------------------------------------------------
  bus_lock: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      dbus_req_o.lock <= '0';
    elsif rising_edge(clk_i) then
      if (ctrl_i.lsu_mo_we = '1') and (ctrl_i.lsu_rmw = '1') and (ctrl_i.ir_funct12(8) = '0') then
        dbus_req_o.lock <= '1'; -- set if Zaamo instruction
      elsif (dbus_rsp_i.ack = '1') or (ctrl_i.cpu_trap = '1') then
        dbus_req_o.lock <= '0'; -- clear at the end of the bus access
      end if;
    end if;
  end process bus_lock;

  -- https://vhdlwhiz.com/ring-buffer-fifo/
  --
  -- When the CPU executes a matrix store instruction, the mem_do_reg process in this file advances
  -- the matrix_mar_store which is the address into matrix engine RAM to store back into
  -- CPU RAM.
  --
  -- The matrix engine RAM will produce the value and place it into the data_in_i port
  -- of this LSU entity.
  --
  -- The LSU entity then has to place that data into a bus store request so that the data
  -- is transferred into CPU RAM.
  --
  PROC_RAM_LSU : process(clk_i)
    variable l : line;
  begin
    if rising_edge(clk_i) then

      load_o <= '0';
      store_o <= '0';

      -- load ::= from CPU RAM into matrix RAM
      if (load = '1') and (dbus_rsp_i_ack = '1') then

        --  -- debug
        --  write(l, String'("LOAD"));
        --  writeline(output, l);
        --  write(l, dbus_rsp_i.data);
        --  writeline(output, l);
--        debug_data_output <= dbus_rsp_i.data;

        -- write external load signal
        load_o <= '1';
        data_out_o <= dbus_rsp_i.data;

      end if;

      -- store ::= from matrix RAM into CPU RAM
      if (store = '1') then

        -- debug
        --  write(l, String'("STORE"));
        --  writeline(output, l);
        --  write(l, ram_i(tail));
        --  writeline(output, l);

--        debug_data_output <= data_in_i;

        -- write external read signal
        store_o <= '1';

        -- rd_data is a dummy value and is currently connected to nothing
        -- rd_data <= ram_i(tail);
        --rd_data <= data_in_i; -- data_in_i is a word from Matrix RAM

        -- -- DEBUG
        -- write(l, data_in_i);
        -- writeline(output, l);

        -- TODO Continue here: Where dbus_req_o.data is written on line 197, mix this shit in and test if
        -- the values F, F, F are written to RAM!

        --dbus_req_o.data <= data_in_i;

        --  write(l, ram_i(tail));
        --  writeline(output, l);

      end if;

    end if;
  end process PROC_RAM_LSU;




  -- Data Input: Alignment and Sign-Extension --------------------------------------------------
  -- LB, LH, LW, LD
  -- -------------------------------------------------------------------------------------------
  mem_di_reg : process(rstn_i, clk_i)
    variable l : line;
  begin

    if (rstn_i = '0') then

      -- DEBUG
      --  write(l, String'("LSU LOAD RESET"));
      --  writeline(output, l);

      rdata_o <= (others => '0');

      matrix_stb_counter_load <= 0;

      -- the mar needs to be read from the instruction
      matrix_mar_load <= matrix_mar_load_store_i;

      matrix_wait_for_load_finished <= '0';

      head_o <= 0;

      load <= '0';

    elsif rising_edge(clk_i) then

      if (not ctrl_i.lsu_m_en = '1') then -- if NO matrix load command is executed, perform normal lb, lh, lw

        rdata_o <= (others => '0'); -- output zero if there is no memory access
        if (pending = '1') then -- pending request
          case ctrl_i.ir_funct3(1 downto 0) is
            when "00" => -- byte
              case mar(1 downto 0) is
                when "00"   => rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(7),  24) & dbus_rsp_i.data(7 downto 0);
                when "01"   => rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(15), 24) & dbus_rsp_i.data(15 downto 8);
                when "10"   => rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(23), 24) & dbus_rsp_i.data(23 downto 16);
                when others => rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(31), 24) & dbus_rsp_i.data(31 downto 24);
              end case;
            when "01" => -- half-word
              if (mar(1) = '0') then -- low half-word
                rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(15), 16) & dbus_rsp_i.data(15 downto 0);
              else -- high half-word
                rdata_o <= replicate_f((not ctrl_i.ir_funct3(2)) and dbus_rsp_i.data(31), 16) & dbus_rsp_i.data(31 downto 16);
              end if;
            when others => -- word
              rdata_o <= dbus_rsp_i.data;
          end case;
        end if;

        -- ML_IDLE, ML_INIT, ML_PROCESS
        matrix_load_state <= ML_INIT;

        matrix_stb_counter_load <= 0;
        head_o <= 0;

        -- DEBUG
        --write(l, String'("LSU LOAD RESET"));
        --writeline(output, l);

      elsif (ctrl_i.ir_funct3(2 downto 0) = "010") then -- if funct3 is the load code

        -- load from CPU RAM into the matrix engine

        case matrix_load_state is

          when ML_IDLE => -- nop
            --write(l, String'("LSU LOAD ML_IDLE"));
            --writeline(output, l);
            load <= '0';

          when ML_INIT =>
            -- write(l, String'("LSU LOAD ML_INIT"));
            -- writeline(output, l);

            matrix_mar_load <= matrix_mar_load_store_i;
            matrix_stb_counter_load <= 0;
            matrix_wait_for_load_finished <= '1';
            head_o <= 0;
            load <= '1';

            -- next state
            matrix_load_state <= ML_PROCESS;

          when ML_PROCESS =>

            if (dbus_rsp_i.ack = '1') then -- need to wait for the cache and the memory to respond before advancing in the state machine

              -- write(l, String'("LSU LOAD ML_PROCESS"));
              -- writeline(output, l);

              if (head_o < 15) then
                matrix_load_state <= ML_INCREMENT;
              else
                matrix_wait_for_load_finished <= '0'; -- done waiting

                -- next state
                matrix_load_state <= ML_IDLE; -- GOTO IDLE state and remain until next activation of the MATRIX LSU
              end if;

              -- keep track of outstanding elements to strobe
              matrix_stb_counter_load <= matrix_stb_counter_load + 1;

              -- advance pointer
              matrix_mar_load <= std_ulogic_vector(unsigned(matrix_mar_load) + 4);

              -- -- debug
              -- write(l, "LSU LOAD: 0x" & to_hstring(unsigned(matrix_mar_load)));
              -- writeline(output, l);

            end if;

          when ML_INCREMENT =>
            head_o <= head_o + 1;
            matrix_load_state <= ML_PROCESS;

          when others =>
            --write(l, String'("LSU LOAD others"));
            --writeline(output, l);

        end case;

      end if;

    end if;

  end process mem_di_reg;


  -- Access Arbiter -------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  access_arbiter: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      pmp_err <= '0';
      pending <= '0';
    elsif rising_edge(clk_i) then
      pmp_err <= pmp_fault_i;
      if (pending = '0') then -- idle
        pending <= ctrl_i.lsu_req;
      elsif (dbus_rsp_i.ack = '1') or (ctrl_i.cpu_trap = '1') then -- bus response or start of trap handling
        pending <= '0';
      end if;
    end if;
  end process access_arbiter;

  -- wait for bus response --
  wait_o <= (matrix_wait_for_load_finished or matrix_wait_for_store_finished) or not dbus_rsp_i.ack;

  -- filter exceptions: RMW-AMOs only cause STORE exceptions --
  exc_rd <= '0' when (ctrl_i.lsu_rmw = '1') else not ctrl_i.lsu_rw;
  exc_wr <= '1' when (ctrl_i.lsu_rmw = '1') else     ctrl_i.lsu_rw;

  -- output access/alignment errors to control unit --
  err_o(0) <= pending and exc_rd and misaligned; -- misaligned load
  err_o(1) <= pending and exc_rd and (dbus_rsp_i.err or pmp_err); -- load bus access error
  err_o(2) <= pending and exc_wr and misaligned; -- misaligned store
  err_o(3) <= pending and exc_wr and (dbus_rsp_i.err or pmp_err); -- store bus access error

  -- access request (all source signals are driven by registers) --
  dbus_req_o.stb <= matrix_stb when ctrl_i.lsu_m_en = '1'
    else ctrl_i.lsu_req and (not misaligned) and (not pmp_fault_i);

  -- address output --
  dbus_req_o.addr <= matrix_mar_load when ((ctrl_i.lsu_m_en = '1') and (load = '1'))
    else matrix_mar_store when ((ctrl_i.lsu_m_en = '1') and (store = '1'))
    else mar;

  -- this signal goes to cpu control lsu_mar_i
  mar_o <= matrix_mar_load when (ctrl_i.lsu_m_en = '1' and (load = '1'))
    else matrix_mar_store when (ctrl_i.lsu_m_en = '1' and (store = '1'))
    else mar; -- for MTVAL CSR

end neorv32_cpu_lsu_rtl;
