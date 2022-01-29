PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS `auth_tokens` (
    `token` TEXT NOT NULL,
    `expires` TEXT NOT NULL,
    `user_id` INTEGER NOT NULL,
    `user_name` TEXT NOT NULL,
    `user_pass` TEXT NOT NULL,
    `host` TEXT NOT NULL,
    PRIMARY KEY(`token`),
    FOREIGN KEY(`user_id`) REFERENCES `users`(`user_id`) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS `user_id_fk_auth_tokens` ON `auth_tokens`(`user_id`);
