package Yaet::Model::Schema;
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
        facebook_token
        facebook_user_id
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
    name 'facebook_album';
    pk 'id';
    columns qw( 
        id
        facebook_user_id
        facebook_object_id
        name
        link
        aid
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

table {
    name 'facebook_photo';
    pk 'id';
    columns qw( 
        id
        ignore_flag
        facebook_user_id
        aid
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
