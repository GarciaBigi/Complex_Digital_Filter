`timescale 1ns/1ps

module fir_serial #(
    parameter integer NB_X = 8, // Number of bits of the input data
    parameter integer NBF_X = 6, // Number of fractional bits of the input data
    parameter integer NB_H = 8, // Number of bits of the coefficients
    parameter integer NBF_H = 7, // Number of fractional bits of the coefficients 
    parameter integer NB_Y = 10, // Number of bits of the output data
    parameter integer NBF_Y = 8,  // Number of fractional bits of the output data
    parameter integer N_TAPS = 8, // Number of taps
    localparam integer NB_ACC = NB_X + NB_H + $clog2(N_TAPS), // Number of bits of the accumulator
    localparam integer NBF_ACC = NBF_X + NBF_H, // Number of fractional bits of the accumulator
    localparam integer NB_PROD = NB_X + NB_H, // Number of bits of the product
    localparam integer NBF_PROD = NBF_X + NBF_H // Number of fractional bits of the product
)(
    input logic clk, // Clock signal
    input logic rst_n, // Asynchronous reset signal (active low)
    input logic s_valid, // Input data valid signal
    input logic [2*NB_X-1:0] s_data, // Input data ({im, re})
    output logic m_valid, // Output data valid signal
    output logic [2*NB_Y-1:0] m_data // Output data ({im, re})
);

    logic signed [NB_X-1:0] x_re, x_im; // Input data (real and imaginary parts)
    logic signed [NB_H-1:0] h [N_TAPS]; // Coefficients (only one component because is a constant real number)
    logic signed [NB_PROD-1:0] prod_re [N_TAPS], prod_im [N_TAPS]; // Product (real and imaginary parts)
    logic signed [NB_ACC-1:0] acc_re, acc_im; // Accumulator (real and imaginary parts)
    logic signed [NB_X-1:0] array_x_re [N_TAPS-1:0], array_x_im [N_TAPS-1:0]; // Array to store the input data (real and imaginary parts)

    assign x_re = s_data[NB_X-1:0]; // Real part of the input data
    assign x_im = s_data[2*NB_X-1:NB_X]; // Imaginary part of the input data
    always_ff @( posedge clk or  negedge rst_n) begin : linea_retardo
        if (!rst_n) begin
            for (int i= 0; i< N_TAPS; i++) begin
                array_x_re[i] <= '0; // Reset input data array to zero
                array_x_im[i] <= '0; // Reset input data array to zero
            end
        end else if (s_valid) begin
            for (int i= 0; i< N_TAPS; i++) begin
                if (i == 0) begin
                    array_x_re[i] <= x_re; // Store the new input data in the first position of the array
                    array_x_im[i] <= x_im; // Store the new input data in the first position of the array
                end else begin
                    array_x_re[i] <= array_x_re[i-1]; // Shift the input data
                    array_x_im[i] <= array_x_im[i-1]; // Shift the input data
                end
            end
        end
    end

    assign h[0] = 1; // Coefficient 0
    assign h[1] = -10; // Coefficient 1
    assign h[2] = 10; // Coefficient 2
    assign h[3] = 62; // Coefficient 3
    assign h[4] = 62; // Coefficient 4
    assign h[5] = 10; // Coefficient 5
    assign h[6] = -10; // Coefficient 6
    assign h[7] = 1; // Coefficient 7

    logic signed [NB_PROD+1-1:0] s1_re[N_TAPS/2-1:0], s1_im[N_TAPS/2-1:0]; // First stage of the adder tree (real and imaginary parts)
    logic signed [NB_PROD+2-1:0] s2_re[N_TAPS/4-1:0], s2_im[N_TAPS/4-1:0]; // Second stage of the adder tree (real and imaginary parts)
    
    always_comb begin : prod_and_acc
        for (int i= 0; i< N_TAPS; i++) begin
            prod_re[i] = array_x_re[i] * h[i]; // Multiply input data by coefficient (real part)
            prod_im[i] = array_x_im[i] * h[i]; // Multiply input data by coefficient (imaginary part)
        end
        for (int k= 0; k< N_TAPS/2; k++) begin
            s1_re[k] = prod_re[2*k] + prod_re[2*k+1]; // First stage of the adder tree (real part)
            s1_im[k] = prod_im[2*k] + prod_im[2*k+1]; // First stage of the adder tree (imaginary part)
        end
        for (int k= 0; k< N_TAPS/4; k++) begin
            s2_re[k] = s1_re[2*k] + s1_re[2*k+1]; // Second stage of the adder tree (real part)
            s2_im[k] = s1_im[2*k] + s1_im[2*k+1]; // Second stage of the adder tree (imaginary part)
        end
        acc_re = s2_re[0] + s2_re[1]; // Final output of the adder tree (real part)
        acc_im = s2_im[0] + s2_im[1]; // Final output of the adder tree (imaginary part)   
    end

    // Rounding and saturation: acc S(NB_ACC,NBF_ACC) -> y S(NB_Y,NBF_Y)
    localparam integer SHIFT = NBF_ACC - NBF_Y; // Fractional bits to drop (5)
    localparam integer NB_SHF = NB_ACC - SHIFT; // Bits left after the shift (14)

    logic signed [NB_ACC-1:0] rnd_re, rnd_im; // acc + half LSB of the output
    logic signed [NB_SHF-1:0] shf_re, shf_im; // rnd >>> SHIFT
    logic signed [NB_Y-1:0] y_re, y_im; // Saturated output

    assign rnd_re = acc_re + (1 <<< (SHIFT - 1)); // Rounding: add half LSB (real part)
    assign rnd_im = acc_im + (1 <<< (SHIFT - 1)); // Rounding: add half LSB (imaginary part)
    assign shf_re = rnd_re >>> SHIFT; // Arithmetic shift (real part)
    assign shf_im = rnd_im >>> SHIFT; // Arithmetic shift (imaginary part)

    // Fits in NB_Y bits if the dropped MSBs and the new sign bit are all equal
    logic fits_re, fits_im; // 1 if there is no overflow

    assign fits_re = (&shf_re[NB_SHF-1:NB_Y-1]) || (~|shf_re[NB_SHF-1:NB_Y-1]);
    assign fits_im = (&shf_im[NB_SHF-1:NB_Y-1]) || (~|shf_im[NB_SHF-1:NB_Y-1]);

    assign y_re = fits_re          ? shf_re[NB_Y-1:0] :         // Fits: keep the low bits
                  shf_re[NB_SHF-1] ? {1'b1, {(NB_Y-1){1'b0}}} : // Negative overflow: minimum
                                     {1'b0, {(NB_Y-1){1'b1}}};  // Positive overflow: maximum
    assign y_im = fits_im          ? shf_im[NB_Y-1:0] :
                  shf_im[NB_SHF-1] ? {1'b1, {(NB_Y-1){1'b0}}} :
                                     {1'b0, {(NB_Y-1){1'b1}}};

     // Output register: the data goes through 2 registers (delay line + output),
    // so valid also goes through 2 (valid_d + m_valid) to stay aligned
    logic valid_d; // 1 if the delay line loaded a new sample in the last clock edge

    always_ff @(posedge clk or negedge rst_n) begin : salida
        if (!rst_n) begin
            valid_d <= 1'b0; // Reset valid pipeline
            m_valid <= 1'b0; // Reset output valid
            m_data  <= '0;   // Reset output data
        end else begin
            valid_d <= s_valid; // Delay valid one clock (delay line stage)
            m_valid <= valid_d; // Delay valid one more clock (output stage)
            if (valid_d) begin
                m_data <= {y_im, y_re}; // Load only when there is a new output ({im, re})
            end
        end
    end

endmodule