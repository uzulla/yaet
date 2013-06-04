package Yaet;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Web::Auth::OAuth2;

use Net::Twitter::Lite::WithAPIv1_1;

use DateTime;
use DateTime::Format::RFC3339;
use Date::Parse;

use Sub::Retry;
use Furl;

use JSON qw/encode_json decode_json/;
use Data::Dumper;

use Yaet::Model;
use CFE::TOLOT::PhotoBook;

use Yaet::Controller::Facebook;

sub startup {
  my $self = shift;

  $self->log->level('debug');

  my $config = $self->plugin('Config');
  $self->secret($config->{mojo_secret});

  my $db = Yaet::Model->new(+{connect_info => ['dbi:SQLite:'.$FindBin::RealBin.'/db.db','','', {sqlite_unicode=>1}]});

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
      on_finished => \&Yaet::Controller::Facebook::on_auth_finished,
  );  

  my $r = $self->routes;

  $r->any('/' => sub {
    my $self = shift;
    if($self->stash('session')->data('user')){
      $self->redirect_to('/facebook/album/list')
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
    my $delete_facebook_photo_num = $self->db->delete('facebook_photo', +{facebook_user_id=> $user->{facebook_user_id}});
    my $delete_facebook_album_num = $self->db->delete('facebook_album', +{facebook_user_id=> $user->{facebook_user_id}});
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

  $r->any('/set_ignore_flag/' => sub{
    my $self = shift;
    my $img_url = $self->param('image');
    my $flag = $self->param('flag');
    my $table = $self->param('data_source_table');
    $self->app->log->debug("set ignore flag : $table $flag $img_url ");

    my $_user = $self->stash('session')->data('user');
    my $user = $self->db->single('user_account', +{id=> $_user->{id}});
    return $self->render_json({status=>'ng', text=>'session not found.' }) unless $user;

    my $update_row_count=0;
    $update_row_count = $self->db->update($table, { ignore_flag => $flag }, { img_std_url => $img_url, facebook_user_id => $user->facebook_user_id } );

    return $self->render_json({status=>'ng', text=>'nothing to update.' }) unless $update_row_count;
    return $self->render_json({status=>'ok', img=>$img_url });
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
      debug         => 1,
      check_img_num => 0,
    } );

    $tlt->set_image_file_list_by_url_list(@images);
    my $temporary_zip_filename = $tlt->create_zip;

    $self->app->log->info("tlt file create done. redirecting to : $config->{base_url}download_temporary/$temporary_zip_filename");
    return $self->render_json({status=>'ok', url=>"$config->{base_url}download_temporary/$temporary_zip_filename"});
  });

  $r->any('/facebook/album/list' => \&Yaet::Controller::Facebook::album_list => 'facebook_album_list' );
  $r->any('/facebook/album/update' => \&Yaet::Controller::Facebook::album_update );
  $r->any('/facebook/album/show/:aid' => \&Yaet::Controller::Facebook::album_show => 'facebook_album_show' );
  $r->any('/facebook/album/show/:aid/update_photo' => \&Yaet::Controller::Facebook::album_photo_update );

}
1;
