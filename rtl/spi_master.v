//==============================================================================
// spi_master.v : SPI master, modes 0-3, parameterized width, MSB/LSB first
// SCLK half-period = clk_div system clocks  (SCLK = clk / (2*clk_div))
// Keep cpol/cpha/lsb_first/clk_div stable while busy.
//==============================================================================
module spi_master #(
    parameter DATA_W = 8
)(
    input  wire              clk,
    input  wire              rst_n,
    // user interface
    input  wire              start,      // 1-cycle pulse, ignored if busy
    input  wire [DATA_W-1:0] tx_data,
    input  wire [15:0]       clk_div,    // >= 1 (use >= 6 if slave oversamples)
    input  wire              cpol,
    input  wire              cpha,
    input  wire              lsb_first,
    output reg  [DATA_W-1:0] rx_data,
    output wire              busy,
    output reg               done,       // 1-cycle pulse when frame finished
    // SPI pins
    output reg               sclk,
    output reg               mosi,
    output reg               cs_n,
    input  wire              miso
);
    localparam IDLE = 2'd0, RUN = 2'd1, FIN = 2'd2;

    reg [1:0]        state;
    reg [15:0]       cnt;                 // half-period counter
    reg [5:0]        edge_cnt;            // SCLK edges so far (0 .. 2*DATA_W-1), DATA_W <= 32
    reg [5:0]        tx_cnt, rx_cnt;      // bits sent / received
    reg [DATA_W-1:0] tx_lat, rx_sh, rx_nxt;

    wire tick        = (cnt == clk_div - 1);
    wire leading     = ~edge_cnt[0];                    // even edge = leading
    wire sample_edge = cpha ? ~leading : leading;       // CPHA=0: sample on leading
    wire [5:0] tx_idx = lsb_first ? tx_cnt : (DATA_W-1-tx_cnt);
    wire [5:0] rx_idx = lsb_first ? rx_cnt : (DATA_W-1-rx_cnt);

    assign busy = (state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; sclk <= 1'b0; cs_n <= 1'b1; mosi <= 1'b0;
            done <= 1'b0;  cnt <= 16'd0; edge_cnt <= 0;
            tx_cnt <= 0;   rx_cnt <= 0;  rx_data <= {DATA_W{1'b0}};
            tx_lat <= {DATA_W{1'b0}};    rx_sh <= {DATA_W{1'b0}};
            rx_nxt <= {DATA_W{1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
            //------------------------------------------------------------------
            IDLE: begin
                sclk     <= cpol;          // idle level follows CPOL
                cs_n     <= 1'b1;
                cnt      <= 16'd0;
                edge_cnt <= 0;
                if (start) begin
                    tx_lat <= tx_data;
                    cs_n   <= 1'b0;
                    mosi   <= tx_data[lsb_first ? 0 : DATA_W-1]; // first bit ready
                    tx_cnt <= cpha ? 0 : 1;  // CPHA=1 re-drives bit0 on 1st edge
                    rx_cnt <= 0;
                    rx_sh  <= {DATA_W{1'b0}};
                    state  <= RUN;
                end
            end
            //------------------------------------------------------------------
            RUN: begin
                if (tick) begin
                    cnt      <= 16'd0;
                    sclk     <= ~sclk;
                    edge_cnt <= edge_cnt + 1;
                    if (sample_edge) begin
                        rx_nxt = rx_sh;
                        rx_nxt[rx_idx] = miso;
                        rx_sh  <= rx_nxt;
                        rx_cnt <= rx_cnt + 1;
                        if (rx_cnt == DATA_W-1) rx_data <= rx_nxt;
                    end else begin
                        if (tx_cnt < DATA_W) begin
                            mosi   <= tx_lat[tx_idx];
                            tx_cnt <= tx_cnt + 1;
                        end
                    end
                    if (edge_cnt == 2*DATA_W-1) state <= FIN;
                end else
                    cnt <= cnt + 1;
            end
            //------------------------------------------------------------------
            FIN: begin                       // hold CS one more half period
                if (tick) begin
                    cs_n  <= 1'b1;
                    done  <= 1'b1;
                    cnt   <= 16'd0;
                    state <= IDLE;
                end else
                    cnt <= cnt + 1;
            end
            default: state <= IDLE;
            endcase
        end
    end
endmodule
