//==============================================================================
// spi_slave.v : SPI slave, modes 0-3, MSB/LSB first
// Oversamples SCLK/CS/MOSI with the system clock (no derived clock -> no CDC
// headaches).  Requires clk >= ~6x SCLK frequency (master clk_div >= 6).
// tx_data must be stable before CS goes low and for the whole frame.
//==============================================================================
module spi_slave #(
    parameter DATA_W = 8
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              cpol,
    input  wire              cpha,
    input  wire              lsb_first,
    input  wire [DATA_W-1:0] tx_data,     // word to send to master
    output reg  [DATA_W-1:0] rx_data,     // word received from master
    output reg               rx_valid,    // 1-cycle pulse when rx_data is new
    // SPI pins
    input  wire              sclk,
    input  wire              mosi,
    input  wire              cs_n,
    output reg               miso
);
    // 2-FF synchronizers (asynchronous inputs -> metastability protection)
    reg sclk_s1, sclk_s2, sclk_prev;
    reg mosi_s1, mosi_s2;
    reg cs_s1,   cs_s2;

    wire rise = sclk_s2 & ~sclk_prev;
    wire fall = ~sclk_s2 & sclk_prev;
    wire leading_edge  = cpol ? fall : rise;
    wire trailing_edge = cpol ? rise : fall;
    wire sample_edge   = cpha ? trailing_edge : leading_edge;
    wire shift_edge    = cpha ? leading_edge  : trailing_edge;

    reg [5:0]        tx_cnt, rx_cnt;      // DATA_W <= 32
    reg [DATA_W-1:0] tx_lat, rx_sh, rx_nxt;
    wire [5:0] tx_idx = lsb_first ? tx_cnt : (DATA_W-1-tx_cnt);
    wire [5:0] rx_idx = lsb_first ? rx_cnt : (DATA_W-1-rx_cnt);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_s1 <= 1'b0; sclk_s2 <= 1'b0; sclk_prev <= 1'b0;
            mosi_s1 <= 1'b0; mosi_s2 <= 1'b0;
            cs_s1   <= 1'b1; cs_s2   <= 1'b1;
            tx_cnt  <= 0;    rx_cnt  <= 0;
            tx_lat  <= {DATA_W{1'b0}}; rx_sh <= {DATA_W{1'b0}};
            rx_nxt  <= {DATA_W{1'b0}};
            rx_data <= {DATA_W{1'b0}}; rx_valid <= 1'b0; miso <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;
            // synchronize
            sclk_s1 <= sclk;  sclk_s2 <= sclk_s1;  sclk_prev <= sclk_s2;
            mosi_s1 <= mosi;  mosi_s2 <= mosi_s1;
            cs_s1   <= cs_n;  cs_s2   <= cs_s1;

            if (cs_s2) begin
                // idle: get ready for next frame (first MISO bit already on pin)
                tx_lat <= tx_data;
                tx_cnt <= cpha ? 0 : 1;
                rx_cnt <= 0;
                rx_sh  <= {DATA_W{1'b0}};
                miso   <= tx_data[lsb_first ? 0 : DATA_W-1];
            end else begin
                if (sample_edge) begin
                    rx_nxt = rx_sh;
                    rx_nxt[rx_idx] = mosi_s2;
                    rx_sh  <= rx_nxt;
                    rx_cnt <= rx_cnt + 1;
                    if (rx_cnt == DATA_W-1) begin
                        rx_data  <= rx_nxt;
                        rx_valid <= 1'b1;
                    end
                end
                if (shift_edge && tx_cnt < DATA_W) begin
                    miso   <= tx_lat[tx_idx];
                    tx_cnt <= tx_cnt + 1;
                end
            end
        end
    end
endmodule
