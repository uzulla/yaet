#!perl
use strict;
use warnings;
use Furl;
use XML::Simple;
use Data::Dumper;
use URI;

my $f = new Furl;
my $google_user_name = "114651309588721895816";

my $uri = URI->new("https://picasaweb.google.com");
$uri->path( 'data/feed/api/user/' . $google_user_name );

$uri->query_form(
    "kind" => "photo",
    "start-index" => 1,
    "max-results" => 10,
    #"fields" => "entry[xs:dateTime(published)>=xs:dateTime('2012-01-01T00:00:00.000Z')](gphoto:id,title,gphoto:timestamp,published,media:group(media:thumbnail,media:content))",
    "fields" => "entry(gphoto:id,title,gphoto:timestamp,published,media:group(media:thumbnail,media:content))",
    "imgmax" => 800
    );

print $uri->as_string;

my $res = $f->get($uri);

die "fail" unless $res->is_success;

my $data = XMLin($res->content);

# published-min, published-max

#print Dumper($data);

print Dumper($data);



#https://lh4.googleusercontent.com/-WXxF_dy_H-k/UWQLW0xwWOI/AAAAAAAADY0/aJSHv_daHac/w432-h324-p-o/20130406-20130406-135915-P40600015915.jpg
