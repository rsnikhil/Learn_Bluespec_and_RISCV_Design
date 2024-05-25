(* synthesize *)
module mkTop (Empty);

   Bit #(32) pc_val = 32'h_8000_1234;

   // Try compile-link-run with each of these variations, one by one
   Bit #(12) page_offset = pc_val [11:0];
   // Bit #(12) page_offset = pc_val [10:0];
   // Bit #(12) page_offset = pc_val [31:20];
   // Bit #(12) page_offset = pc_val [32:20];

   rule rl_once;
      $display ("pc_val = %0h", pc_val);
      $display ("page_offset = %0h", page_offset);
      $finish (0);
   endrule

endmodule
