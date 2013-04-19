use Furl;
use XML::Simple;
use Data::Dumper;
use File::Slurp;

my $furl = Furl->new(
        agent   => 'web danshi/2.0',
        timeout => 10,
    );

#get tag list
#my $res = $furl->get('http://plus.tolot.com/rsc/book/theme/tag_list.xml');
#die $res->status_line unless $res->is_success;
#$tag_list = XMLin($res->content);
#print Dumper($tag_list);

## but notuse 

my $res = $furl->get('http://plus.tolot.com/rsc/book/theme/tag/100.xml'); # 100 is all data
die $res->status_line unless $res->is_success;
$theme_list = XMLin($res->content);
#print Dumper($theme_list);

@theme_id_list = ();
for my $theme (@{$theme_list->{theme_list}->{BookThemeInfo}}){
	#print $theme->{theme_id}."\n";
	push @theme_id_list, $theme->{theme_id};
}

print "ok go download\n";
for my $theme_id (@theme_id_list){
	print "try fetch $theme_id.jpg\n";
	my $res = $furl->get("http://plus.tolot.com/rsc/book/theme/thumbnail/m/$theme_id.jpg");
	die $res->status_line unless $res->is_success;
	write_file("theme_img_dump/$theme_id.jpg", $res->content);
	sleep 1;
}


