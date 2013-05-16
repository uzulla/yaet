package TailF::Controller::Instagram;
use Sub::Retry;
use Data::Dumper;

sub on_auth_finished{
    my ( $c, $access_token, $account_info ) = @_;
    $c->app->log->debug("Instagram API response :".Dumper($account_info));

    my $user = $c->db->single('user_account', +{instagram_id=> $account_info->{data}->{id}});
    unless($user){
      $c->app->log->info("new user account Instagram:".$account_info->{data}->{id});
      my $res = $c->db->insert('user_account', +{ 
        name => $account_info->{data}->{username}, 
        instagram_token => $access_token,
        instagram_id => $account_info->{data}->{id}, 
        avatar_img_url => $account_info->{data}->{profile_picture}, 
        created_at=>0,
        updated_at=>0 
        } );
      $user = $c->db->single('user_account', +{instagram_id=> $account_info->{data}->{id}});
    }

    $c->stash('session')->data('user'=>$user->get_columns);
    $c->app->log->info("logged in ".$account_info->{data}->{username}." by Instagram");
    $c->redirect_to('/mypage');
}

sub mypage {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    unless($user){
      $self->redirect_to('/');
      return;
    }
    my @instagram_photo_list = $self->db->search('instagram_photo', +{ instagram_user_id => $user->{instagram_id} }, +{ limit => 10_000, order_by => 'created_time DESC' } );
    $self->stash(instagram_photo_list => \@instagram_photo_list);
    return $self->render
};

sub update_photo {
    my $self = shift;

    my $user = $self->stash('session')->data('user');

    unless($user){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $config = $self->app->plugin('Config');
    my $instagram = WebService::Instagram->new(
        {
            client_id       => $config->{instagram}->{client_id},
            client_secret   => $config->{instagram}->{client_secret},
            redirect_uri    => $config->{base_url},
        }
    );


    $instagram->set_access_token( $user->{instagram_token} );
    $self->stash(search_result => 0);

    my @newest_instagram_photo = $self->db->search('instagram_photo', +{ instagram_user_id => $user->{instagram_id} }, +{ limit => 1, order_by => 'created_time DESC' } );
    my $limitter = 5000;
    my $params = {};
    if( scalar @newest_instagram_photo > 0){
      $self->app->log->debug("add min time stamp");

      $params = {'min_timestamp'=>$newest_instagram_photo[0]->created_time + 1}
    }

    my $search_result = $instagram->request( 'https://api.instagram.com/v1/users/self/media/recent', $params );

    while(1){
      $limitter--;
      foreach my $i (@{$search_result->{data}}) {
        unless( $self->db->single('instagram_photo', +{'instagram_photo_id'=>$i->{id}} ) ){
          $self->app->log->debug("save img $i->{images}->{thumbnail}->{url}");
          my $res = $self->db->insert('instagram_photo', +{ 
            instagram_user_id => $i->{user}->{id},
            instagram_photo_id => $i->{id},
            link => $i->{link},
            img_std_url => $i->{images}->{standard_resolution}->{url},
            img_std_size => $i->{images}->{standard_resolution}->{width}."x".$i->{images}->{standard_resolution}->{height},
            img_low_url => $i->{images}->{low_resolution}->{url},
            img_low_size => $i->{images}->{low_resolution}->{width}."x".$i->{images}->{low_resolution}->{height},
            img_tmb_url => $i->{images}->{thumbnail}->{url},
            img_tmb_size => $i->{images}->{thumbnail}->{width}."x".$i->{images}->{thumbnail}->{height},
            created_time => $i->{created_time},
            created_at=>0,
            updated_at=>0 
            } );
        }else{
          $self->app->log->warn("try save dup img. $i->{images}->{thumbnail}->{url}. skipped");
        }
      }

      my $next_max_id = $search_result->{pagination}->{next_max_id};

      unless($next_max_id){
        $self->app->log->debug('next_max_id notfound last!');
        last;
      }

      $search_result = retry 5, 2, sub {
        $self->app->log->debug('try instagram :' . $next_max_id);
        $instagram->request( 'https://api.instagram.com/v1/users/self/media/recent', { max_id => $next_max_id } ); 
      };
      unless($search_result){
        $self->app->log->warn("Instagram request error give up");
      }

      if($limitter < 0 ){
        $self->app->log->warn("HIT INSTAGRAM LIMITTER!!!!");
        last;
      }
    }

    return $self->render_json({status=>'ok'});
}

1;