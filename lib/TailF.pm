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
use List::MoreUtils;
use XML::Simple;

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

  my $r = $self->routes;

  $r->any('/' => sub {
    my $self = shift;

    $self->redirect_to('/mypage')
      if($self->stash('session')->data('user'));

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
    my $limitter = 100;
    my $params = {};
    if( scalar @newest_instagram_photo > 0){
      $self->app->log->debug("add min time stamp");

      $params = {'min_timestamp'=>$newest_instagram_photo[0]->created_time + 1}
    }

    my $search_result = $instagram->request( 'https://api.instagram.com/v1/users/self/media/recent', $params );

    while(1){
      $limitter--;
      foreach my $i (@{$search_result->{data}}) {
        #save DB
        $self->app->log->debug("save img $i->{images}->{thumbnail}->{url} \n");
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
    my $semaphore = Coro::Semaphore->new(10); # 10 並列まで

    foreach my $img (@images){
      $counter++;
      if($counter > 100){last;}
      push @coros, async {
        my $guard = $semaphore->guard;
        print "try fetching $img\n";
        my $ua = FurlX::Coro->new(timeout => 10);
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