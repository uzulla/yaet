package TailF::Controller::Picasa;
use Sub::Retry;
use XML::Simple;
use Data::Dumper;

sub on_auth_finished {
  my ( $c, $access_token, $account_info ) = @_;
  $c->app->log->debug("Google API response :".Dumper($account_info));

  my $user = $c->db->single('user_account', +{picasa_id=> $account_info->{id}});
  unless($user){
    $c->app->log->info("new user account Google:".$account_info->{id});
    my $res = $c->db->insert('user_account', +{
      name => $account_info->{displayName},
      picasa_token => $access_token,
      picasa_id => $account_info->{id},
      avatar_img_url => $account_info->{image}->{url},
      created_at=>0,
      updated_at=>0
      } );
    $user = $c->db->single('user_account', +{picasa_id=> $account_info->{id}});
  }

  $c->stash('session')->data('user'=>$user->get_columns);
  $c->app->log->info("logged in ".$account_info->{id}." by Picasa");
  $c->redirect_to('/mypage/picasa');
}

sub mypage  {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    my @picasa_photo_list = $self->db->search('picasa_photo',
      +{ picasa_user_id => $user->{picasa_id} },
      +{ limit => 10_000, order_by => 'created_time DESC' }
      );
    $self->stash(picasa_photo_list => \@picasa_photo_list);
    return $self->render
};

sub update_photo {
    my $PICASA_GET_LIMIT_NUM = 1000;

    my $self = shift;

    my $user = $self->stash('session')->data('user');
    unless($user->{picasa_id}){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $f = new Furl;

    my $uri = URI->new("https://picasaweb.google.com");
    my $google_user_name = $_user->picasa_id;
    $uri->path( 'data/feed/api/user/' . $google_user_name );

    my @newest_picasa_photo = $self->db->search('picasa_photo',
      +{ picasa_user_id => $_user->picasa_id },
      +{ limit => 1, order_by => 'created_time DESC' }
      );

    my $newest_picasa_photo_created = $newest_picasa_photo[0] ? $newest_picasa_photo[0]->created_time : 0 ;
    my $offset = 1;

    while (1) {
      $self->app->log->debug("START get data Picasa API URL");

      $uri->query_form(
          "kind" => "photo",
          "start-index" => $offset,
          "max-results" => $PICASA_GET_LIMIT_NUM,
          "fields" => "entry(gphoto:id,title,gphoto:timestamp,published,media:group(media:thumbnail,media:content))",
          "imgmax" => 800
          );

      my $res = retry 3, 2, sub {
        $self->app->log->debug('try picasa :'.$uri->as_string);
        $f->get($uri);
      }, sub {
        my $res = shift;
        
        if($res->content =~ /Too many results requested/){
          return 0;
        }elsif($res->is_success){
          return 0;
        }else{
          return 1;
        }
      };

      unless($res){
        $self->app->log->warn("Picasa request error give up");
        last;
      }

      if($res->content =~ /Too many results requested/){
        $self->app->log->warn("Picasa request Too many results requested error give up");
        last;
      }

      $self->app->log->debug("Picasa api res:" . Dumper(XMLin($res->content)));

      my $search_result = XMLin($res->content);

      # warn Dumper($search_result->entry);
      # exit;

      last if scalar(@{$search_result->{entry}}) < 1 ;

      my $dt_f = DateTime::Format::RFC3339->new();

      foreach my $i (@{$search_result->{entry}}) {
        if( $newest_picasa_photo_created > $dt_f->parse_datetime($i->{published})->epoch()){
          $self->app->log->debug("reach newest photo : $newest_picasa_photo_created > ".$dt_f->parse_datetime($i->{published})->epoch() );
          return $self->render_json({status=>'ok'}); # debug

        }

        unless( $self->db->single('picasa_photo', +{'picasa_gphoto_id'=>$i->{"gphoto:id"}} ) ){
          $self->app->log->debug("save img $i->{'media:group'}->{'media:content'}->{url}");
          my $res = $self->db->insert('picasa_photo', +{ 
            picasa_user_id => $_user->picasa_id,
            picasa_gphoto_id => $i->{"gphoto:id"},
            img_std_url => $i->{'media:group'}->{'media:content'}->{url},
            img_std_size => $i->{'media:group'}->{'media:content'}->{width}."x".$i->{'media:group'}->{'media:content'}->{height},
            img_tmb_url => $i->{'media:group'}->{'media:thumbnail'}[0]->{url},
            img_tmb_size => $i->{'media:group'}->{'media:thumbnail'}[0]->{width}."x".$i->{'media:group'}->{'media:thumbnail'}[0]->{height},
            created_time => $dt_f->parse_datetime($i->{published})->epoch(),
            created_at=>0,
            updated_at=>0 
            } );
        }else{
          $self->app->log->warn("try save dup img. $i->{'media:group'}->{'media:content'}->{url}. skipped");
        }

      }

      $offset = $offset +$PICASA_GET_LIMIT_NUM ;
      #return $self->render_json({status=>'ok'}); # debug
    };

    return $self->render_json({status=>'ok'});


}

1;