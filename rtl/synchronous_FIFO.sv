module synchronous_FIFO
#(
   parameter int DATA_WIDTH = 32,
   parameter int MEM_DEPTH = 32,
   parameter int ALMOST_EMPTY = MEM_DEPTH / 4,
   parameter int ALMOST_FULL = MEM_DEPTH - MEM_DEPTH / 4
)
(
    input logic clk,
    input logic reset_n,
    input logic write_en,
    input logic read_en,
    input logic [DATA_WIDTH - 1:0] write_data,
    output logic [DATA_WIDTH - 1:0] read_data,
    output logic full,
    output logic almost_full,
    output logic empty,
    output logic almost_empty,
    output logic overflow,
    output logic underflow
);

localparam int ADDRESS_WIDTH = $clog2(MEM_DEPTH);

// synthesis translate_off
initial begin
    if (MEM_DEPTH < 2 || (MEM_DEPTH & (MEM_DEPTH - 1)) != 0) begin
        $error("MEM_DEPTH must be a power of 2 and >= 2, got %0d", MEM_DEPTH);
        $finish;
    end
    if (ALMOST_EMPTY < 1 || ALMOST_FULL >= MEM_DEPTH || ALMOST_EMPTY >= ALMOST_FULL) begin
        $error("Bad thresholds: ALMOST_EMPTY=%0d ALMOST_FULL=%0d MEM_DEPTH=%0d",
               ALMOST_EMPTY, ALMOST_FULL, MEM_DEPTH);
        $finish;
    end
end

// synthesis translate_on
logic [DATA_WIDTH - 1:0] mem [0:MEM_DEPTH - 1];
logic [ADDRESS_WIDTH:0] write_ptr;
logic [ADDRESS_WIDTH:0] read_ptr;
logic [ADDRESS_WIDTH:0] difference;
logic do_write;
logic do_read;

assign empty = (write_ptr == read_ptr);
assign full  = (write_ptr[ADDRESS_WIDTH] != read_ptr[ADDRESS_WIDTH]) && (write_ptr[ADDRESS_WIDTH - 1:0] == read_ptr[ADDRESS_WIDTH - 1:0]);

assign difference = write_ptr - read_ptr;

assign almost_empty = ~empty && (difference <= ALMOST_EMPTY);
assign almost_full  = ~full  && (difference >= ALMOST_FULL);

assign do_write = (write_en && ~full);
assign do_read  = (read_en  && ~empty);

assign overflow  = full  && write_en;
assign underflow = empty && read_en;

always_ff @(posedge clk or negedge reset_n)
begin
if(!reset_n)
    begin
        write_ptr <= '0;
        read_ptr  <= '0;
        read_data <= '0;
    end

    else 
        begin
        if(do_write)
            begin
                mem[write_ptr[ADDRESS_WIDTH - 1:0]] <= write_data;
                write_ptr                           <= write_ptr + 1'b1;
            end

        if(do_read)
            begin
                read_data <= mem[read_ptr[ADDRESS_WIDTH - 1:0]];
                read_ptr  <= read_ptr + 1'b1;
            end
        end
end

endmodule