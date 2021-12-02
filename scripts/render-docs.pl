#!/usr/bin/env perl

use strict;

use Template;
use Data::Dumper;
use JSON::XS;


my $tt = Template->new() || die "$Template::ERROR\n";


my $ctx = loadContracts([qw{
    Euler
    modules/Markets
    modules/Exec
    modules/EToken
    modules/DToken
    modules/Liquidation
    modules/Swap
    PToken
}]);


foreach my $network (qw{ mainnet ropsten }) {
    push @{ $ctx->{networks} }, processNetwork($network);
}



$ctx->{indent} = sub {
    my $txt = shift;
    $txt =~ s{^}{    }mg;
    return $txt;
};

$ctx->{comment} = sub {
    my $txt = shift;
    $txt =~ s{^}{/// }mg;
    return $txt;
};

$ctx->{markdownReturn} = sub {
    my $txt = shift;
    if ($txt =~ /^([a-z]\w+) (.*)/) {
        return "**$1**: $2";
    }
    return $txt;
};


print Dumper($ctx) if $ENV{DUMP};
system("mkdir -p generated");

$tt->process('scripts/templates/contract-reference.md.tt', $ctx, 'generated/contract-reference.md') || die $tt->error();
$tt->process('scripts/templates/IEuler.sol.tt', $ctx, 'generated/IEuler.sol') || die $tt->error();


sub loadContracts {
    my $contracts = shift;

    my @outputs;

    for my $contract (@$contracts) {
        my $file = slurp_file("contracts/$contract.sol");

        if ($contract eq 'Euler') {
            $file .= extraEulerContent();
        } elsif ($contract eq 'modules/Exec') {
            $file = extraExecContent() . $file;
        }

        $contract =~ /(\w+)$/;
        my $name = "IEuler$1";
        $name = "IEuler" if $1 eq 'Euler';

        my $output = {
            name => $name,
        };

        my @lines = split /\n/, $file;

        while (@lines) {
            my $line = shift @lines;

            if ($line =~ m{^\s*///}) {
                my $rec = {};

                while ($line =~ m{^\s*///}) {
                    $line =~ s{^\s*///\s*}{};
                    push @{ $rec->{natspec} }, $line;
                    $line = shift @lines;
                }

                $rec->{natspec} = procNatspec($rec->{natspec});

                if ($line =~ m{^\s*contract}) {
                    $output->{natspec} = $rec->{natspec};
                    next;
                } elsif ($line =~ m{^\s*function (\w+)}) {
                    $rec->{type} = 'function';
                    $rec->{name} = $1;
                    $rec->{def} = cleanupFunction($line);
                } elsif ($line =~ m{^\s*(struct|interface) (\w+)}) {
                    $rec->{type} = $1;
                    $rec->{name} = $2;
                    while ($line !~ m/^\s*\}/) {
                        $rec->{def} .= $line . "\n";
                        $line = shift @lines;
                    }
                    $rec->{def} .= $line;
                    $rec->{def} = deIndent($rec->{def});
                } else {
                    die "unexpected trailing line: $line";
                }

                if ($contract ne 'Euler') {
                    $rec->{def} =~ s{\bAssetConfig\b}{IEuler.AssetConfig}g;
                }

                $rec->{def} =~ s/\bIRiskManager\.//g;

                if ($rec->{type} eq 'interface') {
                    push @{ $output->{preItems} }, $rec;
                } else {
                    push @{ $output->{contractItems} }, $rec;
                }
            }
        }

        push @outputs, $output;
    }

    return { contracts => \@outputs, };
}


sub cleanupFunction {
    my $line = shift;

    $line =~ s/^\s*//;
    $line =~ s/\s*\{\s*$//;

    if ($line =~ m{^function\s+(\w+)\s*\(([^)]*)\)\s*(.*)}) {
        my ($name, $args, $modifiers) = ($1, $2, $3);

        my $ret;
        if ($modifiers =~ m{returns\s*\(.*\)}) {
            $ret = " $&";
        }

        my $stateMode;
        if ($modifiers =~ m{\b(view|pure)\b}) {
            $stateMode = " $1";
        }

        return "function $name($args) external$stateMode$ret;";
    } else {
        die "couldn't parse function line: $line";
    }
}


sub deIndent {
    my $code = shift;
    $code =~ /^(\s*)/;
    my $leading = $1;
    $code =~ s/^$leading//mg;
    return $code;
}


sub procNatspec {
    my $lines = shift;

    my $output = {
        raw => join "\n", @$lines,
    };

    for my $line (@$lines) {
        $line =~ s{^/// }{};
        $line = "\@notice $line" unless $line =~ /^\@/;

        if ($line =~ m{^\@param (\w+)\s*(.*)}) {
            push @{ $output->{params} }, { name => $1, desc => $2, };
        } elsif ($line =~ m{^@(\w+)\s*(.*)}) {
            if ($1 eq 'return') {
                push @{ $output->{$1} }, $2;
            } else {
                $output->{$1} = $2;
            }
        }
    }

    return $output;
}


sub extraEulerContent {
    my $assetConfig = `perl -nE 'print if /struct AssetConfig/ .. /\}/' < contracts/Storage.sol`;
    $assetConfig = deIndent($assetConfig);
    $assetConfig =~ s{[ \t]*//.*?\n}{}g;
    return <<END;
/// \@notice Euler-related configuration for an asset
$assetConfig
END
}

sub extraExecContent {
    my $liquidityStatus = `perl -nE 'print if /struct LiquidityStatus/ .. /\}/' < contracts/IRiskManager.sol`;
    $liquidityStatus = deIndent($liquidityStatus);

    my $assetLiquidity = `perl -nE 'print if /struct AssetLiquidity/ .. /\}/' < contracts/IRiskManager.sol`;
    $assetLiquidity = deIndent($assetLiquidity);

    return <<END;
/// \@notice Liquidity status for an account, either in aggregate or for a particular asset
$liquidityStatus

/// \@notice Aggregate struct for reporting detailed (per-asset) liquidity for an account
$assetLiquidity
END
}





sub processNetwork {
    my $network = shift;

    my $file = "addresses/euler-addresses-$network.json";
    my $addrs = decode_json(slurp_file($file));

    return {
        name => ucfirst($network),
        addrs => $addrs,
    };
}





sub slurp_file {
    my $filename = shift // die "need filename";

    open(my $fh, '<', $filename) || die "couldn't open '$filename' for reading: $!";

    local $/;
    return <$fh>;
}

sub unslurp_file {
    my $contents = shift;
    my $filename = shift;

    open(my $fh, '>', $filename) || die "couldn't open '$filename' for writing: $!";

    print $fh $contents;
}
