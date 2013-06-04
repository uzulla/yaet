PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
DROP TABLE user_account;
CREATE TABLE user_account(
    id integer PRIMARY KEY, 
    name text,
    avatar_img_url text,
    facebook_token text,
    facebook_user_id text,
    created_at text,
    updated_at text
    );
DROP TABLE facebook_album;
CREATE TABLE facebook_album(
    id integer PRIMARY KEY,
    facebook_user_id text,
    facebook_object_id text,
    name text,
    link text,
    aid text,
    created_time text,
    modified_time text,
    created_at text,
    updated_at text
    );
DROP TABLE facebook_photo;
CREATE TABLE facebook_photo(
    id integer PRIMARY KEY,
    ignore_flag integer DEFAULT 0,
    facebook_user_id text,
    aid text,
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
DROP TABLE session;
CREATE TABLE session (
        sid          VARCHAR(40) PRIMARY KEY,
        data         TEXT,
        expires      INTEGER UNSIGNED NOT NULL,
        UNIQUE(sid)
    );
COMMIT;
