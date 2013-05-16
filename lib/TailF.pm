package TailF;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Web::Auth::OAuth2;

use WebService::Instagram;
use Net::Twitter::Lite::WithAPIv1_1;

use DateTime;
use DateTime::Format::RFC3339;
use Date::Parse;

use Sub::Retry;
use Furl;

use JSON qw/encode_json decode_json/;
use Data::Dumper;

use TailF::Model;
use CFE::TOLOT::PhotoBook;

use TailF::Controller::Facebook;
use TailF::Controller::Picasa;
use TailF::Controller::Instagram;

sub startup {
  my $self = shift;

  $self->log->level('debug');

  my $config = $self->plugin('Config');
  $self->secret($config->{mojo_secret});

  my $db = TailF::Model->new(+{connect_info => ['dbi:SQLite:'.$FindBin::RealBin.'/db.db','','']});

  $self->helper( db => sub {return $db} );

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
      on_finished => \&TailF::Controller::Instagram::on_auth_finished,
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
      on_finished => \&TailF::Controller::Facebook::on_auth_finished,
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
      on_finished => \&TailF::Controller::Picasa::on_auth_finished,
  );  

  my $r = $self->routes;

  $r->any('/' => sub {
    my $self = shift;
    if($self->stash('session')->data('user')){
      if($self->stash('session')->data('user')->{instagram_id}){
        $self->redirect_to('/mypage')
      }elsif($self->stash('session')->data('user')->{facebook_id}){
        $self->redirect_to('/mypage/facebook')
      }elsif($self->stash('session')->data('user')->{picasa_id}){
        $self->redirect_to('/mypage/picasa')
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
    my $delete_facebook_photo_num = $self->db->delete('facebook_photo', +{facebook_user_id=> $user->{facebook_id}});
    my $delete_picasa_photo_num = $self->db->delete('picasa_photo', +{picasa_user_id=> $user->{picasa_id}});
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


  $r->any('/create_zip/' => sub{
    my $self = shift;

    my @images = $self->param('images[]');
    unless (@images){
      $self->app->log->warn('images empty');
      die;
    }

    my $tlt = new CFE::TOLOT::PhotoBook( {
      book_title    => "".$self->param('book_title'),
      sub_title     => "".$self->param('sub_title'),
      zip_output_dir=> "$ENV{MOJO_HOME}/public/download_temporary",
      temporary_dir => "$ENV{MOJO_HOME}/tmp",
      data_base_dir => "$ENV{MOJO_HOME}/data/tolot",
      debug         => 1
    } );

    $tlt->set_image_file_list_by_url_list(@images);
    my $temporary_zip_filename = $tlt->create_zip;

    $self->app->log->info("tlt file create done. redirecting to : $config->{base_url}download_temporary/$temporary_zip_filename");
    return $self->render_json({status=>'ok', url=>"$config->{base_url}download_temporary/$temporary_zip_filename"});
  });

  $r->any('/mypage' => \&TailF::Controller::Instagram::mypage => 'mypage');
  $r->any('/update_photo' => \&TailF::Controller::Instagram::update_photo );
  $r->any('/mypage/picasa' => \&TailF::Controller::Picasa::mypage => 'mypage_picasa');
  $r->any('/update_photo/picasa' => \&TailF::Controller::Picasa::update_photo);
  $r->any('/mypage/facebook' => \&TailF::Controller::Facebook::mypage => 'mypage_facebook' );
  $r->any('/update_photo/facebook' => \&TailF::Controller::Facebook::update_photo );

}
1;
