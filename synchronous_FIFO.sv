module synchronous_FIFO
(
    input logic clk,
    input logic reset_n,
    input logic write_en,
    input logic read_en,
    input logic [7:0] write_data,
    output logic [7:0] read_data,
    output logic full,
    output logic almost_full,
    output logic empty,
    output logic almost_empty,
    output logic overflow,
    output logic underflow
);

logic [7:0] mem [0:7];
logic [3:0] write_ptr;
logic [3:0] read_ptr;
logic [3:0] difference;
logic do_write;
logic do_read;

assign empty = (write_ptr == read_ptr);
assign full  = (write_ptr[3] != read_ptr[3]) && (write_ptr[2:0] == read_ptr[2:0]);

assign difference = write_ptr - read_ptr;

assign almost_empty = ~empty && (difference < 4'd3);
assign almost_full  = ~full  && (difference > 4'd4);

assign do_write = (write_en && ~full);
assign do_read  = (read_en  && ~empty);

assign overflow  = full  && write_en;
assign underflow = empty && read_en;

always_ff @(posedge clk or negedge reset_n)
begin
if(!reset_n)
    begin
        write_ptr <= 4'd0;
        read_ptr  <= 4'd0;
        read_data <= 8'd0;
    end

    else 
        begin
        if(do_write)
            begin
                mem[write_ptr[2:0]] <= write_data;
                write_ptr <= write_ptr + 4'd1;
            end

        if(do_read)
            begin
                read_data <= mem[read_ptr[2:0]];
                read_ptr <= read_ptr + 4'd1;
            end
        end
end

endmodule