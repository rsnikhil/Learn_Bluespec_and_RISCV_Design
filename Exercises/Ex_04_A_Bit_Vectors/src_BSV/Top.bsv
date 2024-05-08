(* synthesize *)
module mkTop (Empty);

   // Try compile-link-run with each of these variations, one by one
   Bit #(32) pc_val = 32'h_8000_1000;
   // Bit #(32) pc_val;
   // Bit #(32) pc_val = ?;
   // Bit #(32) pc_val = 33'h_1_8000_1000;
   // Bit #(32) pc_val = 4096;
   // Bit #(32) pc_val = 'h_1000;

   rule rl_once;
      $display ("pc_val = %0h", pc_val);
      $finish (0);
   endrule

endmodule
