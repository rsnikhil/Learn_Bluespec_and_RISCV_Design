package Top;

import DUT :: *;

module mkTop (Empty);

   rule rl_once;
      $display ("Hello, World!");
      $display ("  (From the book: %s", title);
      $display ("   by:            %s", authors);
      $display ("   which was first published on: %4d-%02d-%02d)",
		year, month, day);
      $finish (0);
   endrule

endmodule

endpackage
