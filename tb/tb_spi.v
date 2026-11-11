//==============================================================================
// tb_spi.v : self-checking testbench, SPI master <-> SPI slave loopback
//   - directed tests  : all 4 modes x MSB/LSB first x corner-case data
//   - random tests    : random mode / order / data / clock divider
//   - protocol monitor: SCLK edge count per frame, CS framing, CPOL idle level
//   - prints PASS/FAIL with error count (no waveform inspection needed)
//==============================================================================
`timescale 1ns/1ps
module tb_spi;
    parameter DATA_W = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    // DUT control
    reg              start = 1'b0;
    reg [DATA_W-1:0] m_tx = 0, s_tx = 0;
    reg [15:0]       clk_div = 16'd10;
    reg              cpol = 1'b0, cpha = 1'b0, lsb = 1'b0;

    wire [DATA_W-1:0] m_rx, s_rx;
    wire busy, done, s_valid;
    wire sclk, mosi, miso, cs_n;

    spi_master #(.DATA_W(DATA_W)) u_master (
        .clk(clk), .rst_n(rst_n), .start(start), .tx_data(m_tx),
        .clk_div(clk_div), .cpol(cpol), .cpha(cpha), .lsb_first(lsb),
        .rx_data(m_rx), .busy(busy), .done(done),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .miso(miso));

    spi_slave #(.DATA_W(DATA_W)) u_slave (
        .clk(clk), .rst_n(rst_n), .cpol(cpol), .cpha(cpha), .lsb_first(lsb),
        .tx_data(s_tx), .rx_data(s_rx), .rx_valid(s_valid),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .miso(miso));

    //--------------------------------------------------------------------------
    // Scoreboard counters
    //--------------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;
    integer cov_mode [0:3];                     // simple coverage: mode hit count
    integer cov_lsb  [0:1];

    //--------------------------------------------------------------------------
    // Protocol monitor
    //--------------------------------------------------------------------------
    integer edges = 0;
    reg     in_frame = 1'b0;

    always @(negedge cs_n) begin
        edges    = 0;
        in_frame = 1'b1;
        if (sclk !== cpol) begin
            errors = errors + 1;
            $display("[%0t] MONITOR ERROR: SCLK idle level != CPOL at CS fall", $time);
        end
    end
    always @(sclk) if (in_frame && !cs_n) edges = edges + 1;
    always @(posedge cs_n) begin
        if (in_frame) begin
            if (edges !== 2*DATA_W) begin
                errors = errors + 1;
                $display("[%0t] MONITOR ERROR: %0d SCLK edges in frame, expected %0d",
                          $time, edges, 2*DATA_W);
            end
            in_frame = 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // One full-duplex transfer + automatic check
    //--------------------------------------------------------------------------
    task xfer(input [1:0] mode, input l, input [DATA_W-1:0] md, input [DATA_W-1:0] sd);
        integer t;
        begin
            @(negedge clk);
            {cpol, cpha} = mode;  lsb = l;  m_tx = md;  s_tx = sd;
            repeat (8) @(negedge clk);          // let config settle (CPOL idle level)
            start = 1'b1;  @(negedge clk);  start = 1'b0;
            t = 0;
            while (!done && t < 200000) begin @(posedge clk); t = t + 1; end
            if (!done) begin
                errors = errors + 1;
                $display("[%0t] TIMEOUT waiting for done", $time);
            end
            @(negedge clk);
            checks = checks + 1;
            cov_mode[mode] = cov_mode[mode] + 1;
            cov_lsb[l]     = cov_lsb[l] + 1;
            if (m_rx !== sd) begin
                errors = errors + 1;
                $display("[%0t] FAIL mode=%0d lsb=%0b : master rx=%h expected=%h",
                          $time, mode, l, m_rx, sd);
            end
            if (s_rx !== md) begin
                errors = errors + 1;
                $display("[%0t] FAIL mode=%0d lsb=%0b : slave  rx=%h expected=%h",
                          $time, mode, l, s_rx, md);
            end
            repeat (4) @(negedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Test sequence
    //--------------------------------------------------------------------------
    integer m, l, i;
    initial begin
        $dumpfile("spi.vcd");
        $dumpvars(0, tb_spi);
        cov_mode[0]=0; cov_mode[1]=0; cov_mode[2]=0; cov_mode[3]=0;
        cov_lsb[0]=0;  cov_lsb[1]=0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);

        // ---- Directed: every mode, both bit orders, corner-case data --------
        for (m = 0; m < 4; m = m + 1)
            for (l = 0; l < 2; l = l + 1) begin
                xfer(m, l, 8'hA5, 8'h3C);
                xfer(m, l, 8'h00, 8'hFF);
                xfer(m, l, 8'hFF, 8'h00);
                xfer(m, l, 8'h01, 8'h80);
                xfer(m, l, 8'h80, 8'h01);
                xfer(m, l, 8'h55, 8'hAA);
            end

        // ---- Different clock dividers --------------------------------------
        clk_div = 16'd6;   for (i = 0; i < 20; i = i + 1) xfer(i % 4, 0, $urandom, $urandom);
        clk_div = 16'd25;  for (i = 0; i < 20; i = i + 1) xfer(i % 4, 1, $urandom, $urandom);
        clk_div = 16'd10;

        // ---- Constrained-random --------------------------------------------
        for (i = 0; i < 500; i = i + 1)
            xfer($urandom % 4, $urandom % 2, $urandom, $urandom);

        // ---- Summary --------------------------------------------------------
        $display("------------------------------------------------");
        $display("Transfers checked : %0d", checks);
        $display("Mode coverage     : m0=%0d m1=%0d m2=%0d m3=%0d",
                  cov_mode[0], cov_mode[1], cov_mode[2], cov_mode[3]);
        $display("Bit-order coverage: MSB=%0d LSB=%0d", cov_lsb[0], cov_lsb[1]);
        if (errors == 0) $display("*** TEST PASSED : 0 errors ***");
        else             $display("*** TEST FAILED : %0d errors ***", errors);
        $display("------------------------------------------------");
        $finish;
    end
endmodule
