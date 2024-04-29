A Module and its Interface
==========================

% ----------------------------------------------------------------
(1)

Compile, link and run the given program (Top.bsv, DUT.bsv) using the Makefile.

% ----------------------------------------------------------------
(2)

In DUT.bsv, in 'export DUT_IFC (..)', remove '(..)'.

Try to compile-link-run, and observe the behavior.

% ----------------------------------------------------------------
(3)

Define a third string, say "publisher", in the DUT package; add it as
a third tuple component to the m_title_authors method output; add a
$display() line in mkTop to print it.

% ----------------------------------------------------------------
(4)

In DUT.bsv, define a second module mkDUT2 with the same DUT_IFC
interface.  This module's methods should return information about the
following book:

    "Introduction to VLSI systems"
    Carver Mead and Lynn Conway
    Addison-Wesley, January 1, 1980

In Top.bsv, instantiate mkDUT2 in addition to instantiating mkDUT.

Add some $display statements to print information from this module.
Some nice quotes from the book:

   "We believe that only by carrying along the least amount of
    unnecessary mental baggage at each step in such a study, will the
    student emerge with a good overall understanding of the subject."

   "An atmosphere of excitement and anticipation pervades this field."

% ----------------------------------------------------------------
