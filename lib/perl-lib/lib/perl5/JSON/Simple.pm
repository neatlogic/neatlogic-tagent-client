 ########################################################################## 
##                                                                        ##
##      ###    JSON::Simple 0.1                                           ##
##     #####                                                              ##
##      ###                                                               ##
##             Perl extension for easily producing and parsing JSON.nd    ##
##     ####                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 

# The basics...
    package JSON::Simple;
    use strict;
    use warnings;
    use base 'Exporter';
    our $VERSION = "0.01";
    our @EXPORT = qw(to_json from_json);
    our @EXPORT_OK = qw(json_from_file json_to_file);
    our %EXPORT_TAGS = (
        all         => [qw(to_json from_json json_from_file json_to_file)],
        file        => [qw(                  json_from_file json_to_file)],
    );

    use Carp;
    use Scalar::Util 'looks_like_number';

# Configuration variables.

    # Governs how many levels from a Perl data structure to walk through
    # before throwing an error. Deep Recursion warnings show up when set
    # to 50, so default is 49.
    $JSON::Simple::max_depth = 49;         

    
    # When spitting out JSON, should the names of the name/value pairs
    # in objects be sorted? Set to a true value to enable, to a false value
    # to disable. Default is true.
    $JSON::Simple::sortkeys = 1;

    # Governs whether to_json() and json_to_file should automatically do
    # pretty formatting.
    # Default is 1.
    $JSON::Simple::pretty = 1;

    # The number of spaces for indentation when pretty-formatting JSON.
    $JSON::Simple::indent = 4;


    1;


 
 ########################################################################## 
##                                                                        ##
##      ###    to_json( $ref_to_comlex_data_structure );                  ##
##     #####                                                              ##
##      ###                                                               ##
##             Wrapper to the subroutine that converts a data structure   ##
##     ####    into JSON.                                                 ##
##      ###                                                               ##
##      ###    Returns a JSON string.                                     ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub to_json {
    return _stringify(shift, $JSON::Simple::pretty, 0);
}

 ########################################################################## 
##                                                                        ##
##      ###    _indent( $depth );                                         ##
##     #####                                                              ##
##      ###                                                               ##
##             Interal sub to slap some indentation to a line.            ##
##     ####    Just because I didn't want to write  "    " x $depth       ##
##      ###    all over the place.                                        ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _indent {
    my $depth = shift;
    my $onelevel = " " x $JSON::Simple::indent;
    return $onelevel x $depth;
}

 ########################################################################## 
##                                                                        ##
##      ###    _to_json__format_hash( $hashref, $pretty, $depth );        ##
##     #####                                                              ##
##      ###                                                               ##
##             Takes a hashref and converts it to a JSON object,          ##
##     ####    recursively taking care of references to other hashes and  ##
##      ###    arrays. Optionally adding some pretty formatting.          ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _to_json__format_hash {
    my $hash = shift;
    my $pretty = shift;
    my $depth = shift;

    my $out = "{";
    # only slap newlines after { and before } if both:
    # - pretty formatting, AND
    # - there's more than one name/value pair
    my $slap_newlines = $pretty && (keys(%$hash) > 1);      

    $depth-- unless $slap_newlines; # We don't need deeper indentation
                                    # if we're not going for newlines.

    $out .= "\n" . _indent($depth) if $slap_newlines;

    # Determine the length of the longest key (or name).
    # Used for formatting later.
    my $maxlength_key = 0;
    if ($pretty) {
        for (keys %$hash) {
            $maxlength_key = length($_) if length($_) > $maxlength_key;
        }
        $maxlength_key += 3;
    }
        
    my $pairs = keys %$hash; # how many pairs?
    my $thispair = 0;
    my @keys = keys %$hash;
    @keys = sort @keys if $JSON::Simple::sortkeys;
    for my $k (@keys) {
        $thispair++;
        my $v = _stringify($hash->{$k}, $pretty, $depth);
        $out .= sprintf("%-${maxlength_key}s", _stringify("$k") . ":") . ($pretty ? " " : "") . $v;

        # Only a comma if more name/value pairs follow.
        $out .= "," . ($pretty ? "\n" . _indent($depth) : "") if $thispair < $pairs;
    }
    $out .= ($slap_newlines ? "\n" . _indent($depth-1) : "") . "}";
    return $out;
}

 ########################################################################## 
##                                                                        ##
##      ###    _to_json__format_array( $arrayref, $pretty, $depth );      ##
##     #####                                                              ##
##      ###                                                               ##
##             Takes an array ref and converts it to a JSON object,       ##
##     ####    recursively taking care of references to other hashes and  ##
##      ###    arrays. Optionally adding some pretty formatting.          ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _to_json__format_array {
    my $array = shift;
    my $pretty = shift;
    my $depth = shift;

    my $out = "[";

##                                                                        ##
## TODO:    The body of this subroutine looks a lot like that of          ##
##          _to_json__format_hash. Refactor?                              ##
##   -- P Ramakers, 2011 Sep 12                                           ##
##                                                                        ##
    
    # only slap newlines after { and before } if both:
    # - pretty formatting, AND
    # - there's more than one name/value pair
    my $slap_newlines = $pretty && (@$array > 1);      

    $depth-- unless $slap_newlines; # We don't need deeper indentation
                                    # if we're not going for newlines.

    $out .= "\n" . _indent($depth) if $slap_newlines;

    my $elements = @$array; # how many elements?
    my $thiselement = 0;
    for my $element (@$array) {
        $thiselement++;
        $out .= _stringify($element, $pretty, $depth);

        # Only a comma if more elements will follow.
        $out .= "," . ($pretty ? "\n" . _indent($depth) : "") if $thiselement < $elements;
    }

    $out .= ($slap_newlines ? "\n" . _indent($depth-1) : "") . "]";
}
        
 ########################################################################## 
##                                                                        ##
##      ###    _stringify( $value, $pretty, $depth )                      ##
##     #####                                                              ##
##      ###                                                               ##
##             Takes a Perl value and converts it to JSON. The core of    ##
##     ####    the whole Perl-to-JSON converter.                          ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _stringify {
    my $value = shift;
    my $pretty = shift || 0;
    my $depth = shift || 0;
    
    croak "Data structure too deep. Circular references or \$JSON::Simple::max_depth too low ($JSON::Simple::max_depth)" if $depth > $JSON::Simple::max_depth;

    if (not defined $value) {
        $value = "null";
    }
    elsif ( not ref $value ) {   
        # This returns true when, deep in Perl's internals, Perl thinks
        # that $value is a string.
        my $is_string = ($value ^ $value) eq ("$value" ^ "$value") ? 1 : 0;

        if ($is_string) {
            $value =~ s/\\/\\\\/g;
            $value =~ s/"/\\"/g;
            $value =~ s/\x08/\\t/g;
            $value =~ s/\x09/\\b/g;
            $value =~ s/\x0A/\\n/g;
            $value =~ s/\X0C/\\f/g;
            $value =~ s/\x0D/\\r/g;
            $value = "\"" . _encode_latin1($value) . "\"";
            use utf8;
            utf8::encode($value);
        }
    } elsif (ref $value && UNIVERSAL::isa($value, "JSON::Simple::Boolean")) {
        return "$value";
    } elsif (ref $value eq "HASH") {
        $value = _to_json__format_hash($value, $pretty, $depth + 1);
    } elsif (ref $value eq "ARRAY") {
        $value = _to_json__format_array($value, $pretty, $depth + 1);
    } elsif (ref $value) {
        croak "Unknown reference type " . ref($value) . " ($value)";
    }
    return $value;
}

 ########################################################################## 
##     
## <copypaste>
##
##    ###     Special thanks goes out to
##    ###     Makamaka Hannyaharamitu 
##    ###     for writing JSON:PP
##    ###     from which the following snippet was taken, or by which it
##  #######   was inspired.
##   #####    
##    ###     http://search.cpan.org/~makamaka/JSON-PP-2.27200/lib/JSON/PP.pm
##     #                   
##
##
sub _encode_ascii {
    join('',
        map {
            $_ <= 127 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%x\u%x', _encode_surrogates($_));
        } unpack('U*', $_[0])
    );
}


sub _encode_latin1 {
    join('',
        map {
            $_ <= 255 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%x\u%x', _encode_surrogates($_));
        } unpack('U*', $_[0])
    );
}


sub _encode_surrogates { # from perlunicode
    my $uni = $_[0] - 0x10000;
    return ($uni / 0x400 + 0xD800, $uni % 0x400 + 0xDC00);
}
##
## </copypaste>                              
##
 ########################################################################## 

 ########################################################################## 
##                                                                        ##
##      ###    _parser_lexer( $jsonStr );                                 ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Extracts all JSON tokens from the given      ##
##     ####    string. Throws an error when it runs into something it     ##
##      ###    doesn't recognize. Returns an arrayref of  arrayrefs:      ##
##      ###    [TOKEN TYPE, TOKEN VALUE]                                  ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__lexer {
    my $json = shift;
    my @tokens = (["JSON-ROOT", "(beginning of JSON document)"]);

    my @alltokens = (
        ["JSON-String",         qr/(?:"(?:[^"]|\\u[0-9a-fA-F]{4}|\\.)*"|'(?:[^']|\\u[0-9a-fA-F]{4}|\\.)*')/],
        ["JSON-Number",         qr/-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/],
        ["JSON-Atom",           qr/(?:true|false|null)/],
        ["JSON-Array-Start",    qr/\[/],
        ["JSON-Array-End",      qr/\]/],
        ["JSON-Object-Start",   qr/\{/],
        ["JSON-Object-End",     qr/\}/],
        ["JSON-NameValue-Sep",  qr/:/],
        ["JSON-Value-Sep",      qr/,/],
    );

    my $match = 1;
    while ($match) {
        $match = 0;
        for my $token (@alltokens) {
            if ($json =~ m/\G\s*($token->[1])\s*/gc) {
                push @tokens, [$token->[0], $1];
                $match = 1;
            }
        }
        if (pos($json) < length($json) && not $match) {
            my ($next_nonws) = $json =~ m/\s*(\S+)/;
            croak "Invalid JSON: unrecognized token $next_nonws after <@{$tokens[-1]}>";
        }
    }
    shift @tokens;
    return \@tokens;
}

 ########################################################################## 
##                                                                        ##
##      ###    _parser__next_token_type( $tokens );                       ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Simly returns the type of the next           ##
##     ####    unhandled token. Just there because                        ##
##      ###    _parser__next_token_type($tokens) is easier to read than   ##
##      ###    $tokens->[0]->[0].                                         ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__next_token_type {
    if (@{$_[0]}) {
        return $_[0]->[0]->[0];
        # $_[0]        # the first element in @_ -- it's $tokens
        # ->[0]        # the first element of $tokens -- it's the next token: [$type, $value]
        # ->[0]        # $type
    } else {
        croak "Invalid JSON: missing an expected token";
    }

}

 ########################################################################## 
##                                                                        ##
##      ###    _parser__next_value( $tokens );                            ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Simly returns the value of the next token.   ##
##     ####    This is the core of the parser, because it calls the       ##
##      ###    appropriate subroutines to convert JSON substrings into    ##
##      ###    Perl data structures.                                      ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__next_value {
    my $tokens = shift;
    if (not @{$tokens}) {
        croak "Invalid JSON: missing an expected value";
    }

    my ($type, $value) = @{shift @$tokens};

    if ($type eq "JSON-String") {
        return _parser__handle_string($value);

    } elsif ($type eq "JSON-Number") {
        return $value+0;

    } elsif ($type eq "JSON-Atom") {
        return undef if $value eq "null";
        return JSON::Simple::Boolean->true  if $value eq "true";
        return JSON::Simple::Boolean->false if $value eq "false";
    
    } elsif ($type eq "JSON-Object-Start") {
        return _parser__handle_object($tokens);

    } elsif ($type eq "JSON-Array-Start") {
        return _parser__handle_array($tokens);
    
    } else {
        croak "Invalid JSON: <$type $value> isn't a recognized value";
    }

}

 ########################################################################## 
##                                                                        ##
##      ###    _parser__handle_string( $string )                          ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Casts a JSON string literal to a Perl string ##
##     ####                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__handle_string {
    my $value = shift;
    $value =~ s/^(["'])//g;
    $value =~ s/$1$//g;
    $value =~ s/\\b/chr(8)/ge;
    $value =~ s/\\t/chr(9)/ge;
    $value =~ s/\\f/chr(12)/ge;
    $value =~ s/\\n/chr(10)/ge;
    $value =~ s/\\r/chr(13)/ge;
    $value =~ s/\\u([0-9A-Fa-f]){4}/chr(hex($1))/g;
    $value =~ s/\\(.)/$1/g;
    return $value;
}

 ########################################################################## 
##                                                                        ##
##      ###    _parser__handle_object( $tokens );                         ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Casts a JSON object to a Perl hashref.       ##
##     ####                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__handle_object {
    my $tokens = shift;
    my $object = {};

    while (_parser__next_token_type($tokens) ne "JSON-Object-End") {
        if (_parser__next_token_type($tokens) ne "JSON-String") {
            croak "Invalid JSON: in name/value pair, the name <@{$tokens->[0]}> is not a string";
        }
        my $name = _parser__next_value($tokens);
        croak "Invalid JSON: missing expected name/value seperator <:> between name <$name> and value" if _parser__next_token_type($tokens) ne "JSON-NameValue-Sep";
        shift @$tokens; # eat <:> token

        my $value = _parser__next_value($tokens);
        $object->{$name} = $value;

        my $ok = 0;
        if (_parser__next_token_type($tokens) eq "JSON-Value-Sep" ||
            _parser__next_token_type($tokens) eq "JSON-Object-End"
        ) {
            $ok = 1;
        }

        croak "Invalid JSON: missing expected value seperator <,> or end-of-object token <}> after name/value pair <\"$name\": $value>" if not $ok;

        # Eat commas, even trailing ones.
        shift @$tokens while _parser__next_token_type($tokens) eq "JSON-Value-Sep";
    }
    shift @$tokens; # eat <}> token
    return $object;
}

 ########################################################################## 
##                                                                        ##
##      ###    _parser__handle_array( $tokens );                          ##
##     #####                                                              ##
##      ###                                                               ##
##             Internal sub. Casts a JSON arrayto a Perl arrayref.        ##
##     ####                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub _parser__handle_array {
    my $tokens = shift;
    my $array = [];

    while (_parser__next_token_type($tokens) ne "JSON-Array-End") {
        my $elem = _parser__next_value($tokens);
        push @$array, $elem;

        my $ok = 0;
        if (_parser__next_token_type($tokens) eq "JSON-Value-Sep" ||
            _parser__next_token_type($tokens) eq "JSON-Array-End"
        ) {
            $ok = 1;
        }

        croak "Invalid JSON: missing expected value seperator <,> or end-of-array token <]> after array element <$elem>" if not $ok;

        # Eat commas, even trailing ones.
        shift @$tokens while _parser__next_token_type($tokens) eq "JSON-Value-Sep";
    }
    shift @$tokens; # eat <]> token
    return $array;
}

 ########################################################################## 
##                                                                        ##
##      ###    parse_json( $jsonStr );                                    ##
##     #####                                                              ##
##      ###                                                               ##
##             Wrapper subroutine around _parser__lexer() and             ##
##     ####    _parser__next_value(). It's the public interface for       ##
##      ###    JSON-to-Perl conversion.                                   ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub from_json {
    my $json = shift;
    return _parser__next_value( _parser__lexer( $json ) );
}

 ########################################################################## 
##                                                                        ##
##      ###    json_from_file($filepath)                                  ##
##     #####                                                              ##
##      ###                                                               ##
##             Opens a file, reads its contents, and tries to parse that  ##
##     ####    as JSON.                                                   ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub json_from_file {
    my $filepath = shift;
    open my $fh, "<", $filepath or return undef;
    my $json = join("", <$fh>);
    close $fh;
    return from_json($json);
}

 ########################################################################## 
##                                                                        ##
##      ###    json_to_file( $filepath, $data_structure_ref )             ##
##     #####                                                              ##
##      ###                                                               ##
##             Produces JSON from the provided data structure and dumps   ##
##     ####    it in the specified file.                                  ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub json_to_file {
    my $filepath = shift;
    my $data = shift;
    open my $fh, ">", $filepath or return undef;
    print $fh to_json($data);
    close $fh or return undef;
    return 1;
}

 ########################################################################## 
##                                                                        ##
##      ###    JSON::Simple::true(); JSON::Simple::false();               ##
##     #####                                                              ##
##      ###                                                               ##
##             Easy access to JSON::Simple native Perl representations    ##
##     ####    for the JSON notions of true and false. Not exported.      ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
sub true {     return JSON::Simple::Boolean->true;  }
sub false {    return JSON::Simple::Boolean->false; }



 ########################################################################## 
##                                                                        ##
##      ###    JSON::Simple::Boolean                                      ##
##     #####                                                              ##
##      ###                                                               ##
##             Native Perl representation for the JSON notions of true    ##
##     ####    and false. Evaluates as respectively 1 and 0 in boolean    ##
##      ###    context, and as "true" and "false" when interpolated in a  ##
##      ###    string.                                                    ##
##      ###                                                               ##
##      ###                                                               ##
##    #######                                                             ##
##                                                                        ##
 ########################################################################## 
package JSON::Simple::Boolean;
use Carp;
use overload (
    'bool'  => sub { $_[0]->[0] eq "true" ? 1 : 0 }, 
    '""'    => sub { $_[0]->[0] }
);

sub true {
    my $proto = shift;
    if (ref $proto) { # this is a J::S::B object already
        $proto->[0] = "true";
        return $proto;
    } else {
        my $self = ["true"];
        bless $self, $proto;
        return $self;
    }
}

sub false {
    my $proto = shift;
    if (ref $proto) { # this is a J::S::B object already
        $proto->[0] = "false";
        return $proto;
    } else {
        my $self = ["false"];
        bless $self, $proto;
        return $self;
    }
}

__END__

=head1 NAME

JSON::Simple - Perl extension for easily producing and parsing JSON.

=head1 SYNOPSIS

  use JSON::Simple;
  $json = to_json( $complex_data_structure );       # procudes JSON
  $data = parse_json( $json );                      # parses JSON
  
  # -- OR: --
  
  use JSON::Simple(':file');                        # load only file-related
                                                    #   subroutines.
  json_to_file $filename, $data;                    # store it in a file
  $data = json_from_file $filename;                 # read JSON from file
  
  # -- OR: --
  
  use JSON::Simple(':all');                         # load all subroutines

=head1 DESCRIPTION

JSON (JavaScript Object Notation, L<http://www.json.org>) is a simple to
use format for data exchange, and actually a subset of JavaScript.
JSON::Simple is a module that allows easy production of valid JSON from
complex Perl data structures, and easy parsing of JSON into such data
structures.

JSON::Simple is written out of personal discontent with the interfaces of
existing JSON modules. JSON being a simple format, any modules dealing with
it should be simple to use as well.

=head2 Exported subroutines

By default JSON::Simple exports two subroutines. C<to_json>,
C<to_pretty_json>, and C<from_json>. Two more subroutines are available
on request. They are C<json_to_file> and C<json_from_file>.

Two other subroutines aren't exported but they're accessable by their
full names: C<JSON::Simple::true> and C<JSON::Simple::false>. They're
discussed in-depth in L</Boolean values>.

Easy importing of subroutines can be done through:

  # to_json and parse_json:
  use JSON::Simple;          
  
  # json_to_file and json_from_file:
  use JSON::Simple (':file') 

  # load all:
  use JSON::Simple (':all') 

=head2 to_json

  my $json = to_json( $data );

Produces JSON from an arrayref or hashref.

Will croak when it runs into data that's not representable in JSON. This
normally includes blessed references and things that are neither an
arrayref, a hashref, a string, a number, or an instance of the the special
JSON::Simple::Boolean class.

=head2 parse_json

  my $data = parse_json( $json );

Given a string of valid JSON, parse_json converts that JSON into a native
Perl data structure.

Will croak on invalid JSON.

=head2 json_to_file

  json_to_file( $filepath, $data) or die "Couldn't dump: $!";

Produces JSON from an arrayref or hashref and stores it in the specified
file.

Will croak when it runs into data that's not representable in JSON. This
normally includes blessed references and things that are neither an
arrayref, a hashref, a string, a number, or an instance of the the special
JSON::Simple::Boolean class.

=head2 json_from_file

  $data = json_fron_file( $filepath ) or die "Couldn't read: $!";

Loads a file into memory, tries to parse it as JSON, and builds a native
Perl data structure out of it.

Will croak on invalid JSON.

=head2 JSON::Simple::true

Returns a JSON::Simple::Boolean object representing a boolean C<true>.

In-depth information can be found at L<Boolean values>.

=head2 JSON::Simple::false

Returns a JSON::Simple::Boolean object representing a boolean C<false>.

In-depth information can be found at L<Boolean values>.

=head1 CONFIGURATION

=head2 $JSON::Simple::indent

How many spaces to use for one level of indentation when pretty-formatting
JSON. Defaults to 4.

=head2 $JSON::Simple::max_depth

Defines how deep JSON::Simple should go into a data structure. Since
JSON doesn't really support structures with circular references, but Perl
does, anything with a circular reference will make JSON::Simple go into an
endless loop until your computer runs out of memory.

max_depth helps you prevent that, as JSON::Simple will croak when it is
asked to go deeper into the structure than max_depth.

Defaults to 49, since I emperically discovered that Perl will begin to
throw warnings at you about deep recursion if it's higher.

=head2 $JSON::Simple::pretty

If set to a true value, to_json() and json_to_file() will pretty-format
the JSON they produce.

Defaults to 1.

=head2 $JSON::Simple::sortkeys

Like keys of hashes in Perl, names of name/value pairs in JSON objects aren't
bound to come in any specific order. This variablke, however, tells
JSON::Simple to make an attempt at somehow sorting the keys in the produces
JSON anyway.

Set to a true value to enable, or to false to disable.

Defaults to 1. Even though the sorting gives a little overhead, output is so
much more consistent if name/value pairs come in a predicable order that I
think it's worth it.

=head1 MAPPING

=head2 From Perl to JSON

  In Perl                   In JSON     FORMAT
  ===================================================================
  Array reference           Array       [ELEMENT, ...]
  Hash reference            Object      {"NAME": VALUE, ...}
  String                    String      "VALUE"
  Number                    Number      e.g. 10, or 3.14, ...
  JSON::Simple::Boolean
    blessed reference       Boolean     true or false
  Other reference       (will throw a fatal error)
  undef                     null        null

=head2 From JSON to Perl

  In JSON       In Perl
  ===================================================================
  Array         Array reference
  Object        Hash reference
  String        String
  Number        Number
  Boolean       JSON::Simple::Boolean blessed reference
  null          undef

=head2 Boolean values

JSON, being a subset of JavaScript, supports native booleans. Perl doesn't,
so JSON::Simple uses a workaround to represent booleans in Perl. JSON
booleans become JSON::Simple::Boolean (JSB) objects. Each JSB object
takes a value of either true or false. Through overloading, JSB knows
to return a false value in boolean context and a string (either true or
false) when it's interpolated in a string.

A cool side effect of the JSB design is that you're now effectively
able to use these boolean values in your Perl data structure:

  my $hotel_room = {
    number => 414,
    floor => 4,
    available => JSON::Simple::false
  };

  # translates to JSON as {"number": 414, "floor": 4, "available": false}

  if ( $hotel_room->{available} ) {
      ....
  }

There are two ways to change the JSB object's value. Either you
replace it with another JSB object:

  $hotel_room->{available} = JSON::Simple::true;
  # This is short-hand for:
  $hotel_room->{available} = JSON::Simple::Boolean->true;

Or you just tell the JSB object which value you want it to assume:

  $hotel_room->{available}->true;

Using JSB for a relatively simple thing as this sounds overcomplicated,
but in fact it's not. Other designs were considered, but each of them has
drawbacks that the JSB design overcomes.

=over

=item Use 1 and 0 for true and false

If the JSON parser finds a C<true>, it could translate it to 1 and
a C<false> to 0. That would work, but if you then convert the data 
structure back to JSON again, JSON::Simple wouldn't know that these 1s and
0s were supposed to mean true and false. JSB removes the ambiguity.

=item Use \1 and \0 for true and false

Instead of using plain 1s and 0s for true and false, it would be possible
to use references to 1 and 0 for boolean values.

Initially that was the design, but that would force you to write code 
like C<if ( ${ $hotel_room->{available} } )>. Having you dereference just
because you want to check for trueness or falseness of a variable doesn't
sound right, does it?

=item Use undef for false

No go. Perl's C<undef> and JSON's C<null> are so alike that undef can't
mean anything else than null. That, or JSON::Simple wouldn't be so simple
anymore.

=back

=head1 BUGS AND CAVEATS

=over

=item *

Unicode support is flawed.

=item *

Version 0.01 croaks (throws a fatal error) every time in runs into something it doesn't recognize. JSON::Simple will be more forgiving in a next version.

=back


=head1 SEE ALSO

Introducing JSON: L<http://www.json.org/>

RFC 4627: L<http://tools.ietf.org/html/rfc4627>

=head1 CONTRIBUTERS

Author: P. Ramakers <pramakers@gmail.com> http://www.perlmonks.org/?node=muba

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by P. Ramakers

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
