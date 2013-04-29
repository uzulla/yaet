package TailF::Model::Schema;
use strict;
use warnings;

use Teng::Schema::Declare;
use DateTime::Format::MySQL;

table {
    name 'user_account';
    pk 'id';
    columns qw( 
        id
        name 
        avatar_img_url
        instagram_token 
        instagram_id
        facebook_token
        facebook_id
        created_at
        updated_at 
        );
    inflate qr/_at$/ => sub {
        return DateTime::Format::MySQL->parse_datetime(shift);
    };
    deflate qr/updated_at/ => sub {
        return DateTime::Format::MySQL->format_datetime(DateTime->now());
    };
    deflate qr/created_at/ => sub {
        my $dt = shift;
        if($dt){
            return DateTime::Format::MySQL->format_datetime($dt);
        }else{
            return DateTime::Format::MySQL->format_datetime(DateTime->now());
        }
    };
};


table {
    name 'instagram_photo';
    pk 'id';
    columns qw( 
        id
        instagram_user_id
        instagram_photo_id
        link
        img_std_url
        img_std_size
        img_low_url
        img_low_size
        img_tmb_url
        img_tmb_size
        created_time
        created_at
        updated_at
        );
    inflate qr/_at$/ => sub {
        return DateTime::Format::MySQL->parse_datetime(shift);
    };
    deflate qr/updated_at/ => sub {
        return DateTime::Format::MySQL->format_datetime(DateTime->now());
    };
    deflate qr/created_at/ => sub {
        my $dt = shift;
        if($dt){
            return DateTime::Format::MySQL->format_datetime($dt);
        }else{
            return DateTime::Format::MySQL->format_datetime(DateTime->now());
        }
    };
};

table {
    name 'facebook_photo';
    pk 'id';
    columns qw( 
        id
        facebook_user_id
        facebook_object_id
        img_std_url
        img_std_size
        img_tmb_url
        img_tmb_size
        created_time
        modified_time
        created_at
        updated_at
        );
    inflate qr/_at$/ => sub {
        return DateTime::Format::MySQL->parse_datetime(shift);
    };
    deflate qr/updated_at/ => sub {
        return DateTime::Format::MySQL->format_datetime(DateTime->now());
    };
    deflate qr/created_at/ => sub {
        my $dt = shift;
        if($dt){
            return DateTime::Format::MySQL->format_datetime($dt);
        }else{
            return DateTime::Format::MySQL->format_datetime(DateTime->now());
        }
    };
};


1;