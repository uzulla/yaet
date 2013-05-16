PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
DROP TABLE user_account;
CREATE TABLE user_account(
    id integer PRIMARY KEY, 
    name text,
    avatar_img_url text,
    instagram_token text,
    instagram_id text,
    facebook_token text,
    facebook_id text,
    picasa_token text,
    picasa_id text,
    created_at text,
    updated_at text
    );
--ALTER TABLE user_account ADD COLUMN picasa_token text;
--ALTER TABLE user_account ADD COLUMN picasa_id text;

DROP TABLE instagram_photo;
CREATE TABLE instagram_photo(
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
DROP TABLE facebook_photo;
CREATE TABLE facebook_photo(
    id integer PRIMARY KEY,
    facebook_user_id text,
    facebook_object_id text,
    img_std_url text,
    img_std_size text,
    img_tmb_url text,
    img_tmb_size text,
    created_time text,
    modified_time text,
    created_at text,
    updated_at text
    );
DROP TABLE picasa_photo;
CREATE TABLE picasa_photo(
    id integer PRIMARY KEY,
    picasa_user_id text,
    picasa_gphoto_id text,
    img_std_url text,
    img_std_size text,
    img_tmb_url text,
    img_tmb_size text,
    created_time text,
    created_at text,
    updated_at text
    );
DROP TABLE session;
CREATE TABLE session (
        sid          VARCHAR(40) PRIMARY KEY,
        data         TEXT,
        expires      INTEGER UNSIGNED NOT NULL,
        UNIQUE(sid)
    );
COMMIT;