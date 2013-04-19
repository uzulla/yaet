create table user_account(
    id integer PRIMARY KEY, 
    name text,
    avatar_img_url text,
    instagram_token text,
    instagram_id text,
    created_at text,
    updated_at text
    );

create table instagram_photo(
    id integer PRIMARY KEY,
    instagram_user_id text,
    instagram_photo_id text,
    link text,
    img_std_url text,
    img_std_size text,
    img_low_url text,
    img_low_size text,
    img_tmb_url text,
    img_tmb_size text,
    created_time text,
    created_at text,
    updated_at text
    );

