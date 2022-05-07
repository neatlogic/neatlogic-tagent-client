#!/usr/bin/perl
use strict;
use Crypt::RC4;

my $passphrase = 'ts9012501';
my $plaintext = '1234567890';

sub rc4_encrypt_hex ($$) {  
    my ($key, $data) = ($_[0], $_[1]);  
    return join('',unpack('H*',RC4($key, $data)));  
}  
  
sub rc4_decrypt_hex ($$) {  
    my ($key, $data) = ($_[0], $_[1]);  
    return RC4($key, pack('H*',$data));  
}  
  
my $encrypted = rc4_encrypt_hex($passphrase, $plaintext);  
my $decrypted = rc4_decrypt_hex($passphrase, $encrypted);  
  
print "plain test: ", $plaintext, "\nafter encrypt: ",$encrypted,"\nafter decrypt: ",$decrypted,"\n"  
