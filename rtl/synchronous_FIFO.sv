module synchronous_FIFO
(
    input logic clk,
    input logic reset_n,
    input logic write_en,
    input logic read_en,
    input logic [7:0] write_data,
    output logic [7:0] read_data,
    output logic full,
    output logic empty
);

logic [7:0] mem [0:3];
logic [2:0] write_ptr;
logic [2:0] read_ptr;
logic do_write;
logic do_read;

assign empty = (write_ptr == read_ptr);
assign full = (write_ptr[2] != read_ptr[2]) && (write_ptr[1:0] == read_ptr[1:0]);

assign do_write = (write_en && ~full);
assign do_read = (read_en && ~empty);

always_ff @(posedge clk or negedge reset_n)
begin
if(!reset_n)
    begin
        write_ptr <= 3'd0;
        read_ptr <= 3'd0;
        read_data <= 8'd0;
    end

    else 
        begin
        if(do_write)
            begin
                mem[write_ptr[1:0]] <= write_data;
                write_ptr <= write_ptr + 3'd1;
            end

        if(do_read)
            begin
                read_data <= mem[read_ptr[1:0]];
                read_ptr <= read_ptr + 3'd1;
            end
        end
end

endmodule