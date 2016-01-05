use Test::More;
use Devel::Peek;
use version;

BEGIN { use_ok( 'Net::LDNS' ) }

my $lib_v = version->parse(Net::LDNS::lib_version());
ok( $lib_v >= v1.6.16, 'ldns version at least 1.6.16' );

SKIP: {
    skip 'no network', 59 if $ENV{TEST_NO_NETWORK};

    my $s = Net::LDNS->new( '8.8.8.8' );
    isa_ok( $s, 'Net::LDNS' );
    my $p = $s->query( 'nic.se', 'MX' );
    isa_ok( $p, 'Net::LDNS::Packet' );
    is( $p->rcode, 'NOERROR', 'expected rcode' );

    my $p2 = $s->query( 'iis.se', 'NS', 'IN' );
    isa_ok( $p2, 'Net::LDNS::Packet' );
    is( $p2->rcode, 'NOERROR' );
    is( $p2->opcode, 'QUERY', 'expected opcode' );
    my $pround = Net::LDNS::Packet->new_from_wireformat( $p2->wireformat );
    isa_ok( $pround, 'Net::LDNS::Packet' );
    is( $pround->opcode, $p2->opcode, 'roundtrip opcode OK' );
    is( $pround->rcode,  $p2->rcode,  'roundtrip rcode OK' );

    ok( $p2->id() > 0, 'packet ID set' );
    ok( $p2->qr(),     'QR bit set' );
    ok( !$p2->aa(),    'AA bit not set' );
    ok( !$p2->tc(),    'TC bit not set' );
    ok( $p2->rd(),     'RD bit set' );
    ok( !$p2->cd(),    'CD bit not set' );
    ok( $p2->ra(),     'RA bit set' );
    ok( !$p2->ad(),    'AD bit not set' );
    ok( !$p2->do(),    'DO bit not set' );

    ok( $p2->querytime > 0 );
    is( $p2->answerfrom, '8.8.8.8', 'expected answerfrom' );
    $p2->answerfrom( '1.2.3.4' );
    is( $p2->answerfrom, '1.2.3.4', 'setting answerfrom works' );

    ok($p2->timestamp > 0, 'has a timestamp to begin with');
    $p2->timestamp( 4711 );
    is( $p2->timestamp, 4711, 'setting timestamp works' );
    $p2->timestamp( 4711.4711 );
    ok( $p2->timestamp - 4711.4711 < 0.0001, 'setting timestamp works with microseconds too' );

    eval { $s->query( 'nic.se', 'gurksallad', 'CH' ) };
    like( $@, qr/Unknown RR type: gurksallad/ );

    eval { $s->query( 'nic.se', 'SOA', 'gurksallad' ) };
    like( $@, qr/Unknown RR class: gurksallad/ );

    eval { $s->query( 'nic.se', 'soa', 'IN' ) };
    ok( !$@ );

    my @answer = $p2->answer;
    is( scalar( @answer ), 3, 'expected number of NS records in answer' );
    my %known_ns = map { $_ => 1 } qw[ns.nic.se. i.ns.se. ns3.nic.se.];
    foreach my $rr ( @answer ) {
        isa_ok( $rr, 'Net::LDNS::RR::NS' );
        is( lc($rr->owner), 'iis.se.', 'expected owner name' );
        ok( $rr->ttl > 0, 'positive TTL (' . $rr->ttl . ')' );
        is( $rr->type,  'NS', 'type is NS' );
        is( $rr->class, 'IN', 'class is IN' );
        ok( $known_ns{ lc($rr->nsdname) }, 'known nsdname (' . $rr->nsdname . ')' );
    }

    my %known_mx = map { $_ => 1 } qw[mx1.iis.se. mx2.iis.se. ];
    foreach my $rr ( $p->answer ) {
        is( $rr->preference, 10, 'expected MX preference' );
        ok( $known_mx{ lc($rr->exchange) }, 'known MX exchange (' . $rr->exchange . ')' );
    }

    my $lroot = Net::LDNS->new( '199.7.83.42' );
    my $se = $lroot->query( 'se', 'NS' );

    is( scalar( $se->question ),   1,  'one question' );
    is( scalar( $se->answer ),     0,  'zero answers' );
    is( scalar( $se->authority ),  9,  'nine authority' );
    my $add = scalar( $se->additional );
    ok( $add == 16 || $add == 15, 'sixteen additional' );

    my $rr = Net::LDNS::RR->new_from_string(
        'se. 172800	IN	SOA	catcher-in-the-rye.nic.se. registry-default.nic.se. 2013111305 1800 1800 864000 7200' );
    my $rr2 =
      Net::LDNS::RR->new( 'se.			172800	IN	TXT	"SE zone update: 2013-11-13 15:08:28 +0000 (EPOCH 1384355308) (auto)"' );
    ok( $se->unique_push( 'answer', $rr ), 'unique_push returns ok' );
    is( $se->answer, 1, 'one record in answer section' );
    ok( !$se->unique_push( 'answer', $rr ), 'unique_push returns false' );
    is( $se->answer, 1, 'still one record in answer section' );
    ok( $se->unique_push( 'ansWer', $rr2 ), 'unique_push returns ok again' );
    is( $se->answer, 2, 'two records in answer section' );
}

my $made = Net::LDNS::Packet->new( 'foo.com', 'SOA', 'IN' );
isa_ok( $made, 'Net::LDNS::Packet' );

foreach my $flag (qw[do qr tc aa rd cd ra ad]) {
    ok(!$made->$flag(), uc($flag).' not set');
    $made->$flag(1);
    ok($made->$flag(), uc($flag).' set');
}

is($made->edns_size, 0, 'Initial EDNS0 UDP size is 0');
ok($made->edns_size(4096));
is($made->edns_size, 4096, 'EDNS0 UDP size set to 4096');
ok(!$made->edns_size(2**17), 'Setting to too big did not work'); # Too big

is($made->edns_rcode, 0, 'Extended RCODE is 0');
$made->edns_rcode(1);
is($made->edns_rcode, 1, 'Extended RCODE is 1');

is($made->type, 'answer');

done_testing;
