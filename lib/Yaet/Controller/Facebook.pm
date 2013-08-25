package Yaet::Controller::Facebook;
use Sub::Retry;
use JSON qw/encode_json decode_json/;
use Data::Dumper;

sub on_auth_finished {
  my ( $c, $access_token, $account_info ) = @_;
  $c->app->log->debug("Facebook API response :".Dumper($account_info));

  my $user = $c->db->single('user_account', +{facebook_user_id=> $account_info->{id}});
  unless($user){
    $c->app->log->info("new user account Facebook:".$account_info->{id});
    my $res = $c->db->insert('user_account', +{ 
      name => $account_info->{name}, 
      facebook_token => $access_token,
      facebook_user_id => $account_info->{id}, 
      avatar_img_url => "http://graph.facebook.com/$account_info->{id}/picture", 
      created_at=>0,
      updated_at=>0 
      } );
    $user = $c->db->single('user_account', +{facebook_user_id=> $account_info->{id}});
  }else{
    my $config = $c->app->plugin('Config');
    $extended_token = getUpdateToken($c, $config->{facebook}->{app_id},$config->{facebook}->{app_secret}, $access_token);
    $c->app->log->debug('extended token :'.$extended_token);
    $user->facebook_token($extended_token);
    $user->update; 
  }

  $c->stash('session')->data('user'=>$user->get_columns);
  $c->app->log->info("logged in ".$account_info->{name}." by Facebook");
  $c->redirect_to('/');
}

sub getUpdateToken {
    my ($c, $client_id, $client_secret, $facebook_token) = @_;

    my $f = new Furl;
    my $uri = URI->new("https://graph.facebook.com");
    $uri->path( 'oauth/access_token' );
    $uri->query_form(
        client_id=>$client_id,
        client_secret=>$client_secret,
        grant_type=>"fb_exchange_token",
        fb_exchange_token => $facebook_token,
        );
    my $res = $f->get($uri)->content;
    #$c->app->log->debug('getUpdateToken res :'.$res);
    $res =~ /access_token=(.+)&expires=/;
    return $1;
}

sub album_show  {
    my $self = shift;
    my $user = $self->stash('session')->data('user');

    my $aid = $self->param('aid');

    my $album = $self->db->single('facebook_album',
      +{ facebook_user_id => $user->{facebook_user_id}, aid => $aid }
      );

    my @photo_list = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_user_id}, aid => $aid },
      +{ limit => 10_000, order_by => 'created_time DESC' }
      );

    $self->stash(album => $album);    
    $self->stash(photo_list => \@photo_list);    
    $self->stash(user => $user);    
    return $self->render
};

sub album_list  {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    my @album_list = $self->db->search('facebook_album',
      +{ facebook_user_id => $user->{facebook_user_id} },
      +{ limit => 10_000, order_by => 'modified_time DESC' }
      );
    $self->stash(album_list => \@album_list);    
    $self->stash(user => $user);    
    return $self->render
};

sub album_update {
    my $FACEBOOK_LIMIT_NUM = 1000;
    my $FACEBOOK_HARD_LIMIT_NUM = 5000;

    my $self = shift;

    my $user = $self->stash('session')->data('user');
    unless($user->{facebook_user_id}){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $f = new Furl;

    my $uri = URI->new("https://graph.facebook.com");
    $uri->path( 'fql' );

    my $offset = 0;
    while (1) {
      $uri->query_form(
        access_token => $_user->facebook_token,
        encode => "json",
        q => "
          SELECT object_id,aid,name,link,created,modified 
          FROM album 
          WHERE owner = me()
          ORDER BY modified
          LIMIT $FACEBOOK_LIMIT_NUM 
          OFFSET $offset
        "
        );

      my $res = retry 3, 2, sub {
        $self->app->log->debug('try facebook :'.$uri->as_string);
        $f->get($uri);
      }, sub {
        my $res = shift;
        $res->is_success ? 0 : 1;
      } ;

      unless($res){
        $self->app->log->warn("Facebook request error give up");
        last;
      }

      $self->app->log->debug("facebook api res:" . Dumper(decode_json($res->content)));

      my $search_result = decode_json($res->content);
      last if scalar(@{$search_result->{data}}) < 1 ;

      foreach my $i (@{$search_result->{data}}) {
        my $album = $self->db->single('facebook_album', +{'facebook_object_id'=>$i->{object_id}} );
        unless( $album ){
          $self->app->log->debug("save album $i->{link}");
          my $res = $self->db->insert('facebook_album', +{ 
            facebook_user_id => $_user->facebook_user_id,
            facebook_object_id => $i->{object_id},
            name => $i->{name},
            link => $i->{link},
            aid => $i->{aid},
            created_time => $i->{created},
            modified_time => $i->{modified},
            created_at=>0,
            updated_at=>0 
            } );
        }else{
          $self->app->log->debug("udpate album $i->{link}");
          $album->update(+{
            name => $i->{name},
            created_time =>$i->{created},
            modified_time => $i->{modified},
          });
        }
      }

      $offset = $offset +$FACEBOOK_LIMIT_NUM ;
      last if $offset > $FACEBOOK_HARD_LIMIT_NUM;
    };

    return $self->render_json({status=>'ok'});
}



sub album_photo_update {
    my $FACEBOOK_LIMIT_NUM = 1000;
    my $FACEBOOK_HARD_LIMIT_NUM = 5000;

    my $self = shift;

    my $user = $self->stash('session')->data('user');
    unless($user->{facebook_user_id}){
      $self->redirect_to('/');
      return;
    }

    my $aid = $self->param('aid');

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $f = new Furl;

    my $uri = URI->new("https://graph.facebook.com");
    $uri->path( 'fql' );

    my @newest_facebook_photo = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_user_id} },
      +{ limit => 1, order_by => 'created_time DESC' }
      );

    #delete old
    $self->db->delete('facebook_photo', +{'facebook_user_id'=>$user->{facebook_user_id}, 'aid'=>$aid } );

    my $newest_facebook_photo_created = 0; # DISABLE #$newest_facebook_photo[0] ? $newest_facebook_photo[0]->created_time : 0 ;
    my $offset = 0;

    while (1) {
      $self->app->log->debug("START get data Facebook API URL");
      $uri->query_form(
        access_token => $_user->facebook_token,
        encode => "json",
        q => "
          SELECT object_id,src,src_height,src_width,src_big,src_big_height,src_big_width,aid,created,modified 
          FROM photo 
          WHERE owner = me() AND created > $newest_facebook_photo_created AND aid = $aid
          ORDER BY created
          LIMIT $FACEBOOK_LIMIT_NUM 
          OFFSET $offset
        "
        );

      my $res = retry 3, 2, sub {
        $self->app->log->debug('try facebook :'.$uri->as_string);
        $f->get($uri);
      }, sub {
        my $res = shift;
        $res->is_success ? 0 : 1;
      } ;

      unless($res){
        $self->app->log->warn("Facebook request error give up");
        last;
      }

      $self->app->log->debug("facebook api res:" . Dumper(decode_json($res->content)));

      my $search_result = decode_json($res->content);
      last if scalar(@{$search_result->{data}}) < 1 ;

      foreach my $i (@{$search_result->{data}}) {
        unless( $self->db->single('facebook_photo', +{'facebook_object_id'=>$i->{object_id}} ) ){
          $self->app->log->debug("save img $i->{src}");
          #warn Dumper($i);
          my $res = $self->db->insert('facebook_photo', +{ 
            facebook_user_id => $_user->facebook_user_id,
            facebook_object_id => $i->{object_id},
            aid => $i->{aid},
            img_std_url => $i->{src_big},
            img_std_size => $i->{src_big_width}."x".$i->{src_big_height},
            img_tmb_url => $i->{src},
            img_tmb_size => $i->{src_width}."x".$i->{src_height},
            created_time => $i->{created},
            modified_time => $i->{modified},
            created_at=>0,
            updated_at=>0 
            } );
        }else{
          $self->app->log->warn("dup image? umm strange... img was delete first... $i->{images}->{thumbnail}->{url}. skipped");
        }
      }

      $offset = $offset +$FACEBOOK_LIMIT_NUM ;
      last if $offset > $FACEBOOK_HARD_LIMIT_NUM;
    };

    #update bigger img size
    @target_photo_list = $self->db->search('facebook_photo',
      +{ facebook_user_id=>$user->{facebook_user_id}, aid=>$aid }
      );

    $target_photo_id_list = [];
    for my $target_photo ( @target_photo_list ){
      push @$target_photo_id_list, $target_photo->facebook_object_id;
    }

    $self->app->log->debug("START get data Facebook API URL for get BIGGER img src");
    $uri->query_form(
      access_token => $_user->facebook_token,
      encode => "json",
      q => "
        select photo_id,src,width,height 
        FROM photo_src
        WHERE photo_id IN (". join(',', @$target_photo_id_list) .") AND (width > 720 OR height > 720) 
      "
      );

    my $res = retry 3, 2, sub {
      $self->app->log->debug('try facebook :'.$uri->as_string);
      $f->get($uri);
    }, sub {
      my $res = shift;
      $res->is_success ? 0 : 1;
    } ;

    $self->app->log->debug("facebook api res:" . Dumper(decode_json($res->content)));

    my $search_result = decode_json($res->content);

    my $_photo_list = {};

    foreach my $i (@{$search_result->{data}}) {
      my $_tmp = {
        photo_id=>$i->{photo_id},
        width=> $i->{width},
        height=> $i->{height},
        src=> $i->{src}
      };

      unless($_photo_list->{$i->{photo_id}}){
        $_photo_list->{$i->{photo_id}} = $_tmp;
      }else{
        $_photo_list->{$i->{photo_id}} = $_tmp if $i->{width} > $_photo_list->{$i->{photo_id}}->{width} ;
      }
    }

    foreach my $k (keys %$_photo_list){
      my $i = $_photo_list->{$k};
      $self->db->update('facebook_photo',
        +{
          img_std_url=>$i->{src},
          img_std_size=>$i->{width}."x".$i->{height}
          },
        +{facebook_object_id=>$i->{photo_id}}
         );
    }

    return $self->render_json({status=>'ok'});
}

1;
