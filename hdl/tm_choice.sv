module tm_choice (input wire [7:0] data_in, output logic [8:0] qm_out);

    logic [3:0] n_1;

    always_comb begin
        n_1 = data_in[0];
        for (integer i=1; i<8; i=i+1) begin
            n_1 = n_1 + data_in[i];
        end

        qm_out[0] = data_in[0];
        if (n_1 > 4 || (n_1 == 4 && data_in[0] == 0)) begin
            for (integer i=0; i<7; i=i+1) begin
                qm_out[i+1] = ~(qm_out[i] ^ data_in[i+1]);
            end
            qm_out[8] = 0;
        end else begin
            for (integer i=0; i<7; i=i+1) begin
                qm_out[i+1] = qm_out[i] ^ data_in[i+1];
            end
            qm_out[8] = 1;
        end
    end

endmodule //end tm_choice
