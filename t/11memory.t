use Test;
BEGIN { 
    if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
        plan tests => 19;
    }
    else {
        plan tests => 0;
        print "# Skipping test on this platform\n";
    }
}
use XML::LibXML;
{
    if ($^O eq 'linux' && $ENV{MEMORY_TEST}) {
        require Devel::Peek;
        my $peek = 0;
    
        ok(1);

        my $times_through = $ENV{MEMORY_TIMES} || 100_000;
    
        print("# BASELINE\n");
        check_mem(1);

        print("# MAKE DOC IN SUB\n");
        {
            my $doc = make_doc();
            ok($doc);
            ok($doc->toString);
        }
        check_mem();
        print("# MAKE DOC IN SUB II\n");
        # same test as the first one. if this still leaks, it's
        # our problem, otherwise it's perl :/
        {
            my $doc = make_doc();
            ok($doc);

            ok($doc->toString);
        }
        check_mem();

        {
            my $elem = XML::LibXML::Element->new("foo");
            my $elem2= XML::LibXML::Element->new("bar");
            $elem->appendChild($elem2);
            ok( $elem->toString );
        }
        check_mem();

        print("# SET DOCUMENT ELEMENT\n");
        {
            my $doc2 = XML::LibXML::Document->new();
            make_doc_elem( $doc2 );
            ok( $doc2 );
            ok( $doc2->documentElement );
        }
        check_mem();

        # multiple parsers:
        print("# MULTIPLE PARSERS\n");
        for (1..$times_through) {
            my $parser = XML::LibXML->new();
        }
        ok(1);

        check_mem();

        # multiple parses
        print("# MULTIPLE PARSES\n");
        for (1..$times_through) {
            my $parser = XML::LibXML->new();
            my $dom = $parser->parse_string("<sometag>foo</sometag>");
        }
        ok(1);

        check_mem();

        # multiple failing parses
        print("# MULTIPLE FAILURES\n");
        for (1..$times_through) {
            # warn("$_\n") unless $_ % 100;
            my $parser = XML::LibXML->new();
            eval {
                my $dom = $parser->parse_string("<sometag>foo</somtag>"); # Thats meant to be an error, btw!
            };
        }
        ok(1);
    
        check_mem();

        # building custom docs
        print("# CUSTOM DOCS\n");
        my $doc = XML::LibXML::Document->new();
        for (1..$times_through)        {
            my $elem = $doc->createElement('x');
            
            if($peek) {
                warn("Doc before elem\n");
                Devel::Peek::Dump($doc);
                warn("Elem alone\n");
                Devel::Peek::Dump($elem);
            }
            
            $doc->setDocumentElement($elem);
            
            if ($peek) {
                warn("Elem after attaching\n");
                Devel::Peek::Dump($elem);
                warn("Doc after elem\n");
                Devel::Peek::Dump($doc);
            }
        }
        if ($peek) {
            warn("Doc should be freed\n");
            Devel::Peek::Dump($doc);
        }
        ok(1);
        check_mem();

        print("# DTD string parsing\n");

        my $dtdstr;
        {
            local $/; local *DTD;
            open(DTD, 'example/test.dtd') || die $!;
            $dtdstr = <DTD>;
            $dtdstr =~ s/\r//g;
            $dtdstr =~ s/[\r\n]*$//;
            close DTD;
        }

        ok($dtdstr);

        for ( 1..$times_through ) {
            my $dtd = XML::LibXML::Dtd->parse_string($dtdstr);
        }
        ok(1);
        check_mem();

        print( "# DTD URI parsing \n");
        # parse a DTD from a SYSTEM ID
        for ( 1..$times_through ) {
            my $dtd = XML::LibXML::Dtd->new('ignore', 'example/test.dtd');
        }
        ok(1);
        check_mem();

        print("# Document validation\n");
        {
            print "# is_valid()\n";
            my $dtd = XML::LibXML::Dtd->parse_string($dtdstr);
            my $xml = XML::LibXML->new->parse_file('example/article_bad.xml');
            for ( 1..$times_through ) {
                $xml->is_valid($dtd);
            }
            ok(1);
            check_mem();
        
            print "# validate() \n";
            for ( 1..$times_through ) {
                eval { $xml->validate($dtd);};
            }
            ok(1);
            check_mem();
                
        }

        print "# FIND NODES \n";
        {
            my $str = "<foo><bar><foo/></bar></foo>";
            my $doc = XML::LibXML->new->parse_string( $str );
            for ( 1..$times_through ) {
                my @nodes = $doc->findnodes("/foo/bar/foo");
            }
            ok(1);
            check_mem();

        }

        {
            my $str = "<foo><bar><foo/></bar></foo>";
            my $doc = XML::LibXML->new->parse_string( $str );
            for ( 1..$times_through ) {
                my $nodes = $doc->find("/foo/bar/foo");
            }
            ok(1);
            check_mem();

        }
    }
}

sub make_doc {
    # code taken from an AxKit XSP generated page
    my ($r, $cgi) = @_;
    my $document = XML::LibXML::Document->createDocument("1.0", "UTF-8");
    # warn("document: $document\n");
    my ($parent);

    { 
        my $elem = $document->createElement(q(p));
        $document->setDocumentElement($elem); 
        $parent = $elem; 
    }

    $parent->setAttribute("xmlns:" . q(param), q(http://axkit.org/XSP/param));
    
    { 
        my $elem = $document->createElementNS(q(http://axkit.org/XSP/param),q(param:foo),);
        $parent->appendChild($elem);
        $parent = $elem;
    }

    $parent = $parent->parentNode;
    # warn("parent now: $parent\n");
    $parent = $parent->parentNode;
    # warn("parent now: $parent\n");

    return $document
}

sub check_mem {
    my $initialise = shift;
    # Log Memory Usage
    local $^W;
    my %mem;
    if (open(FH, "/proc/self/status")) {
        my $units;
        while (<FH>) {
            if (/^VmSize.*?(\d+)\W*(\w+)$/) {
                $mem{Total} = $1;
                $units = $2;
            }
            if (/^VmRSS:.*?(\d+)/) {
                $mem{Resident} = $1;
            }
        }
        close FH;

        if ($LibXML::TOTALMEM != $mem{Total}) {
            warn("LEAK! : ", $mem{Total} - $LibXML::TOTALMEM, " $units\n") unless $initialise;
            $LibXML::TOTALMEM = $mem{Total};
        }

        print("# Mem Total: $mem{Total} $units, Resident: $mem{Resident} $units\n");
    }
}

# some tests for document fragments
sub make_doc_elem {
    my $doc = shift;
    my $dd = XML::LibXML::Document->new();
    my $node1 = $doc->createElement('test1');
    my $node2 = $doc->createElement('test2');
    $doc->setDocumentElement( $node1 );
}

