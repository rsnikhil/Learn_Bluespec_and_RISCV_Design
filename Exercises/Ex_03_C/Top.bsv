package Top;

import DUT :: *;

module mkTop (Empty);

   DUT_IFC dut <- mkDUT;

   rule rl_once;
      match { .title, .authors }   = dut.m_title_authors;
      match { .year, .month, .day} = dut.m_date;

      $display ("Hello, World!");
      $display ("  (From the book: %s", title);
      $display ("   by:            %s", authors);
      $display ("   which was first published on: %4d-%02d-%02d)",
		year, month, day);
      $finish (0);
   endrule

endmodule

endpackage
