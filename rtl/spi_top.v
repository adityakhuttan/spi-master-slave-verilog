//==============================================================================
// spi_top.v : SPI master + slave wired together (loopback).
// Use this as the synthesis/implementation top (out-of-context) to get
// meaningful LUT / FF / timing / power numbers for the whole design.
//==============================================================================
module spi_top #(
    parameter DATA_W = 8
)(
    input  wire              clk,
    input  wire              rst_n,
    // configuration
    input  wire [15:0]       clk_div,
    input  wire              cpol,
    input  wire              cpha,
    input  wire              lsb_first,
    // master user interface
    input  wire              start,
    input  wire [DATA_W-1:0] m_tx_data,
    output wire [DATA_W-1:0] m_rx_data,
    output wire              busy,
    output wire              done,
    // slave user interface
    input  wire [DATA_W-1:0] s_tx_data,
    output wire [DATA_W-1:0] s_rx_data,
    output wire              s_rx_valid
);
    wire sclk, mosi, miso, cs_n;

    spi_master #(.DATA_W(DATA_W)) u_master (
        .clk(clk), .rst_n(rst_n), .start(start), .tx_data(m_tx_data),
        .clk_div(clk_div), .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first),
        .rx_data(m_rx_data), .busy(busy), .done(done),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .miso(miso));

    spi_slave #(.DATA_W(DATA_W)) u_slave (
        .clk(clk), .rst_n(rst_n), .cpol(cpol), .cpha(cpha), .lsb_first(lsb_first),
        .tx_data(s_tx_data), .rx_data(s_rx_data), .rx_valid(s_rx_valid),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .miso(miso));
endmodule
