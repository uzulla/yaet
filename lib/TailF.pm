package TailF;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Web::Auth::OAuth2;
use TailF::Model;
use Net::Twitter::Lite::WithAPIv1_1;
use DateTime;
use Data::Dumper;
use WebService::Instagram;
use Try::Tiny;
use Sub::Retry;
use LWP::UserAgent;
use File::Temp qw/tempfile/;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Slurp;
use Coro;
use FurlX::Coro;
use Furl;
use List::MoreUtils;
use XML::Simple;
use Date::Parse;
use DateTime::Format::RFC3339;
use JSON qw/encode_json decode_json/;

sub startup {
  my $self = shift;

  $self->log->level('debug');

  my $config = $self->plugin('Config');
  $self->secret($config->{mojo_secret});

  my $db = TailF::Model->new(+{connect_info => ['dbi:SQLite:'.$FindBin::RealBin.'/db.db','','']});

  $self->helper( db => sub {return $db} );

  my $instagram = WebService::Instagram->new(
      {
          client_id       => $config->{instagram}->{client_id},
          client_secret   => $config->{instagram}->{client_secret},
          redirect_uri    => $config->{base_url},
      }
  );

  $self->plugin(
    session => {
      stash_key => 'session',
      store     => [dbi => {dbh => $db->dbh}],
      transport => 'cookie',
      expires_delta => 1209600, #2 weeks.
      init      => sub{
        my ($self, $session) = @_;
        $session->load;
        if(!$session->sid){
          $session->create;
        }
      },
    }
  );

  #/auth/instagram/authenticate
  $self->plugin( 'Web::Auth',
      module      => 'Instagram',
      key         => $config->{instagram}->{client_id},
      secret      => $config->{instagram}->{client_secret},
      on_error    => sub {
          my ( $c, @__ ) = @_;
          my ( $error_info ) = @__;
          $self->app->log->info("Instagram auth error $error_info");
          $c->redirect_to('/');
      },
      on_finished => sub {
          my ( $c, $access_token, $account_info ) = @_;
          $self->app->log->debug("Instagram API response :".Dumper($account_info));

          my $user = $c->db->single('user_account', +{instagram_id=> $account_info->{data}->{id}});
          unless($user){
            $self->app->log->info("new user account Instagram:".$account_info->{data}->{id});
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
          $self->app->log->debug("user_account row :".Dumper($user->get_columns));

          $c->stash('session')->data('user'=>$user->get_columns);

          $self->app->log->info("logged in ".$account_info->{data}->{username}." by Instagram");

          $c->redirect_to('/mypage');
      },
  );  

  #/auth/facebook/authenticate
  $self->plugin( 'Web::Auth',
      module      => 'Facebook',
      key         => $config->{facebook}->{app_id},
      secret      => $config->{facebook}->{app_secret},
      scope       => 'user_photos',
      on_error    => sub {
          my ( $c, @__ ) = @_;
          my ( $error_info ) = @__;
          $self->app->log->info("Facebook auth error $error_info");
          $c->redirect_to('/');
      },
      on_finished => sub {
          my ( $c, $access_token, $account_info ) = @_;
          $self->app->log->debug("Facebook API response :".Dumper($account_info));

          my $user = $c->db->single('user_account', +{facebook_id=> $account_info->{id}});
          unless($user){
            $self->app->log->info("new user account Facebook:".$account_info->{id});
            my $res = $c->db->insert('user_account', +{ 
              name => $account_info->{name}, 
              facebook_token => $access_token,
              facebook_id => $account_info->{id}, 
              avatar_img_url => "http://graph.facebook.com/$account_info->{id}/picture", 
              created_at=>0,
              updated_at=>0 
              } );
            $user = $c->db->single('user_account', +{facebook_id=> $account_info->{id}});
          }
          $self->app->log->debug("user_account row :".Dumper($user->get_columns));

          $c->stash('session')->data('user'=>$user->get_columns);

          $self->app->log->info("logged in ".$account_info->{name}." by Facebook");

          $c->redirect_to('/mypage/facebook');
      },
  );  

  #/auth/google/authenticate
  $self->plugin( 'Web::Auth',
      module      => 'Google',
      key         => $config->{google}->{client_id},
      secret      => $config->{google}->{client_secret},
      on_error    => sub {
          my ( $c, @__ ) = @_;
          my ( $error_info ) = @__;
          $self->app->log->info("Picasa auth error $error_info");
          $c->redirect_to('/');
      },
      on_finished => sub {
          my ( $c, $access_token, $account_info ) = @_;
          warn Dumper($c);
          warn Dumper($access_token);
          warn Dumper($account_info);

          $self->app->log->debug("Google API response :".Dumper($account_info));

          my $user = $c->db->single('user_account', +{picasa_id=> $account_info->{id}});
          unless($user){
            $self->app->log->info("new user account Google:".$account_info->{id});
            my $res = $c->db->insert('user_account', +{ 
              name => $account_info->{data}->{username}, 
              picasa_token => $access_token,
              picasa_id => $account_info->{id}, 
              avatar_img_url => $account_info->{image}, 
              created_at=>0,
              updated_at=>0 
              } );
            $user = $c->db->single('user_account', +{picasa_id=> $account_info->{id}});
          }
          $self->app->log->debug("user_account row :".Dumper($user->get_columns));

          $c->stash('session')->data('user'=>$user->get_columns);

          $self->app->log->info("logged in ".$account_info->{data}->{username}." by Picasa");

          $c->redirect_to('/mypage/picasa');
      },
  );  

  my $r = $self->routes;

  $r->any('/mypage/picasa' => sub {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    my @picasa_photo_list = $self->db->search('picasa_photo',
      +{ picasa_user_id => $user->{picasa_id} },
      +{ limit => 10_000, order_by => 'created_time DESC' }
      );
    $self->stash(picasa_photo_list => \@picasa_photo_list);
    return $self->render
  } => 'mypage_picasa');

  $r->any('/update_photo/picasa' => sub {
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
  });



  $r->any('/mypage/facebook' => sub {
    my $self = shift;
    my $user = $self->stash('session')->data('user');
    my @facebook_photo_list = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_id} },
      +{ limit => 10_000, order_by => 'created_time DESC' }
      );
    $self->stash(facebook_photo_list => \@facebook_photo_list);    
    return $self->render
  } => 'mypage_facebook');

  $r->any('/update_photo/facebook' => sub {
    my $FACEBOOK_LIMIT_NUM = 1000;
    my $FACEBOOK_HARD_LIMIT_NUM = 5000;

    my $self = shift;

    my $user = $self->stash('session')->data('user');
    unless($user->{facebook_id}){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    my $f = new Furl;

    my $uri = URI->new("https://graph.facebook.com");
    $uri->path( 'fql' );

    my @newest_facebook_photo = $self->db->search('facebook_photo',
      +{ facebook_user_id => $user->{facebook_id} },
      +{ limit => 1, order_by => 'created_time DESC' }
      );

    my $newest_facebook_photo_created = $newest_facebook_photo[0] ? $newest_facebook_photo[0]->created_time : 0 ;
    my $offset = 0;
    while (1) {
      $self->app->log->debug("START get data Facebook API URL");
      $uri->query_form(
        access_token => $_user->facebook_token,
        encode => "json",
        q => "
          SELECT object_id,src,src_height,src_width,src_big,src_big_height,src_big_width,created,modified 
          FROM photo 
          WHERE owner = me() AND created > $newest_facebook_photo_created
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
          $self->app->log->debug("save img $i->{images}->{thumbnail}->{url}");
          $self->app->log->debug("save img $i->{src}");
          my $res = $self->db->insert('facebook_photo', +{ 
            facebook_user_id => $_user->facebook_id,
            facebook_object_id => $i->{object_id},
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
          $self->app->log->warn("try save dup img. $i->{images}->{thumbnail}->{url}. skipped");
        }

      }

      $offset = $offset +$FACEBOOK_LIMIT_NUM ;
      last if $offset > $FACEBOOK_HARD_LIMIT_NUM;
    };

    return $self->render_json({status=>'ok'});
  });

  $r->any('/' => sub {
    my $self = shift;

    if($self->stash('session')->data('user')){
      if($self->stash('session')->data('user')->{instagram_id}){
        $self->redirect_to('/mypage')
      }elsif($self->stash('session')->data('user')->{facebook_id}){
        $self->redirect_to('/facebook/mypage')
      }
    }

    return $self->render
  } => 'index');

  $r->any('/erase' => sub{
    my $self = shift;
    my $user = $self->stash('session')->data('user');

    unless($user){
      $self->redirect_to('/');
      return;
    }

    my $delete_instagram_photo_num = $self->db->delete('instagram_photo', +{instagram_user_id=> $user->{instagram_id}});
    my $delete_user_account_num = $self->db->delete('user_account', +{id=> $user->{id}});

    $self->redirect_to('/auth/logout');
  });

  $r->any('/auth/logout' => sub{
    my $self = shift;
    $self->app->log->info('user logout.');
    $self->stash('session')->clear;
    $self->session(expires=>1);
    $self->redirect_to('/');
  });

  $r->any('/mypage' => sub {
    my $self = shift;
    
    my $user = $self->stash('session')->data('user');

    unless($user){
      $self->redirect_to('/');
      return;
    }

    my @instagram_photo_list = $self->db->search('instagram_photo', +{ instagram_user_id => $user->{instagram_id} }, +{ limit => 10_000, order_by => 'created_time DESC' } );

    $self->stash(instagram_photo_list => \@instagram_photo_list);

    return $self->render
  } => 'mypage');


  $r->any('/update_photo' => sub {
    my $self = shift;

    my $user = $self->stash('session')->data('user');

    unless($user){
      $self->redirect_to('/');
      return;
    }

    my $_user = $self->db->single('user_account', +{id=> $user->{id}});

    $instagram->set_access_token( $user->{instagram_token} );
    $self->stash(search_result => 0);

    my @newest_instagram_photo = $self->db->search('instagram_photo', +{ instagram_user_id => $user->{instagram_id} }, +{ limit => 1, order_by => 'created_time DESC' } );

    my $limitter = 1000;
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
        last;
      }
    }

    return $self->render_json({status=>'ok'});
  });


  $r->any('/create_zip/' => sub{
    my $self = shift;

    my @images = $self->param('images[]');
    $self->app->log->debug("request images list: ".Dumper(@images));
    unless (@images){
      $self->app->log->warn('images empty');
      die;
    }

    my $book_title = $self->param('book_title');
    my $sub_title = $self->param('sub_title');

    my @tmp_filename_list = ();
    my $counter = -1;

    my @coros;
    my $semaphore = Coro::Semaphore->new(4); # 4 並列まで
    my $ua = FurlX::Coro->new(timeout => 10);
    foreach my $img (@images){
      $counter++;
      if($counter > 100){last;}
      push @coros, async {
        my $guard = $semaphore->guard;
        $self->app->log->debug("try fetching $img");
        
        my $response = $ua->get($img);
        if ($response->is_success) {
          my $idx =  List::MoreUtils::firstidx { $_ eq $img } @images;
          $self->app->log->debug( "dl success : $idx" );
          my ($fh, $filename) = tempfile('img_XXXX', DIR => "$ENV{MOJO_HOME}/tmp");
          print $fh $response->decoded_content;
          $tmp_filename_list[$idx] = $filename;
          close $fh;
        } else {
          $self->app->log->warn("Image download fail url-> $img");
          die $response->status_line;
        }
      }
    }
    $_->join for @coros; # wait done.

    $self->app->log->info('image dl complete');
    $self->app->log->debug(Dumper(@tmp_filename_list));

    # make zip
    my $zip = Archive::Zip->new();

    #tolot meta data
    $zip->addDirectory('tolot/OEBPS/');
    $zip->addDirectory('tolot/OEBPS/images/');
    $zip->addDirectory('tolot/OEBPS/texts/');
    $zip->addDirectory('tolot/OEBPS/tolot/');

    $zip->addFile( "$ENV{MOJO_HOME}/data/tolot/content.opf", 'tolot/OEBPS/content.opf');

    for(my $i=0;$i<62;$i++){
      $zip->addFile( "$ENV{MOJO_HOME}/data/tolot/texts/page$i.xhtml", "tolot/OEBPS/texts/page$i.xhtml");
    }

    my @theme_code_list = List::Util::shuffle ("5121","5122","5123","5124","5125","5126","5127","5128","5129","5130","5131","5132","6145","6146","6147","6148","6149","6150","6151","6152");
    my $book_xml = XMLin("$ENV{MOJO_HOME}/data/tolot/book.xml");
    $book_xml->{title} = $book_title;
    $book_xml->{themeCode} = $theme_code_list[0];
    $book_xml->{subTitle} = $sub_title  ;
    $zip->addString( XMLout( $book_xml, NoAttr => 1, RootName => 'book',XMLDecl => "<?xml version='1.0' encoding='UTF-8'?>" ), 'tolot/OEBPS/tolot/book.xml');

    $zip->addFile( "$ENV{MOJO_HOME}/data/tolot/info.xml", 'tolot/OEBPS/tolot/info.xml');

    my $filename_num = 0;
    foreach my $filename (@tmp_filename_list){
      my $file_member = $zip->addFile( $filename, "tolot/OEBPS/images/$filename_num.jpg");
      $filename_num++;
    }

    my $temporary_zip_filename = sub{join"",map{$_[rand@_]}1..40}->("a".."z",0..9,"A".."Z") . ".tlt";
    open my $zipfh, "> $ENV{MOJO_HOME}/public/download_temporary/$temporary_zip_filename";
    $zip->writeToFileHandle($zipfh, 0);
    close $zipfh ;

    $self->app->log->info('zip filename: '.$temporary_zip_filename);

    foreach my $filename (@tmp_filename_list){
      $self->app->log->debug( "delete img file: ". $filename );
      unlink $filename;
    }

    $self->app->log->info("tlt file create done. redirecting to : $config->{base_url}download_temporary/$temporary_zip_filename");
    return $self->render_json({status=>'ok', url=>"$config->{base_url}download_temporary/$temporary_zip_filename"});
  });

}
1;
