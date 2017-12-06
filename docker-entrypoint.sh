#!/bin/sh

set -x

prepare_config(){
  [ -e $1 ] || return 1
  local basename=`basename $1`
  cp -pf $1.example /home/git/data/config/example
  cp -pf $1 /home/git/data/config/
}

link_config(){
  local basename=`basename $1`
  rm -f $1
  ln -s /home/git/data/config/$basename $1
}

diff_config(){
  local basename=`basename $1`
  diff $1.example /home/git/data/config/example/$basename.example || exit 1
}

# set default
DB_HOST=${DB_HOST:-gitlab-postgres}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-gitlabhq_production}
DB_USER=${DB_USER:-gitlab}
DB_PASS=${DB_PASS:-gitlabpassword}

env PGPASSWORD="$DB_PASS" psql -h $DB_HOST -d $DB_NAME -U $DB_USER -c \
"SELECT true AS enabled FROM pg_available_extensions WHERE name = 'pg_trgm' AND installed_version IS NOT NULL;" || exit 1

REDIS_HOST=${REDIS_HOST:-gitlab-redis}
REDIS_PORT=${REDIS_PORT:-6379}

if [ ! -d /home/git/data/config ];then
  mkdir -p /home/git/data/config
  mkdir -p /home/git/data/config/example
  chown -R git:git /home/git/data/config
  
  cp -pf /home/git/gitlab/config/database.yml.postgresql /home/git/gitlab/config/database.yml.example
  cp -pf /home/git/gitlab/lib/support/nginx/gitlab /etc/nginx/conf.d/gitlab.conf.example
  
  sed -i \
  -e "s|database: .*$|database: $DB_NAME|g" \
  -e "s|username: .*$|username: $DB_USER|g" \
  -e "s|password: .*$|password: $DB_PASS|g" \
  -e "s|host: .*$|host: $DB_HOST|g" \
  -e "s|port: .*$|port: $DB_PORT|g" \
    /home/git/gitlab/config/database.yml
  
  sed -i \
  -e "s|unix:.*$|redis://$REDIS_HOST:$REDIS_PORT|g" \
    /home/git/gitlab/config/resque.yml
  
  sed -i \
  -e "s|host: .*$|host: $REDIS_HOST|g" \
  -e "s|http://localhost/|http://localhost:8080/|g" \
    /home/git/gitlab-shell/config.yml
  
  while read line;do
    prepare_config $line
  done < configfile_list.txt
fi

cp -pf /home/git/gitlab/config/database.yml.postgresql /home/git/gitlab/config/database.yml.example
cp -pf /home/git/gitlab/lib/support/nginx/gitlab /etc/nginx/conf.d/gitlab.conf.example
while read line;do
  diff_config $line
  link_config $line
done < configfile_list.txt

mkdir -p /home/git/data/.ssh
mkdir -p /home/git/data/repositories
mkdir -p /home/git/data/uploads
mkdir -p /home/git/data/builds
mkdir -p /home/git/data/backups
chown git:git /home/git/data/.ssh /home/git/data/repositories /home/git/data/uploads /home/git/data/builds /home/git/data/backups
mkdir -p /home/git/data/shared/artifacts/tmp/cache /home/git/data/shared/artifacts/tmp/uploads
mkdir -p /home/git/data/shared/lfs-objects /home/git/data/shared/pages
mkdir -p /home/git/data/shared/cache/archive
chown -R git:git /home/git/data/shared

ln -s /home/git/data/uploads /home/git/gitlab/public/uploads
rm -rf /home/git/gitlab/builds
ln -s /home/git/data/builds /home/git/gitlab/builds
ln -s /home/git/data/backups /home/git/gitlab/tmp/backups
rm -rf /home/git/gitlab/shared
ln -s /home/git/data/shared /home/git/gitlab/shared
rm -rf /home/git/gitlab/log
ln -s /var/log/gitlab /home/git/gitlab/log
chown git:git /var/log/gitlab

[ -e /home/git/data/tmp/VERSION ] && diff /home/git/data/tmp/VERSION /home/git/gitlab/VERSION

cd /home/git/gitlab
env PGPASSWORD="$DB_PASS" psql -h $DB_HOST -d $DB_NAME -U $DB_USER -c \
"SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;" \
  | grep "$DB_NAME" | grep 'kB$' \
&& { echo "yes" | sudo -u git -H bundle exec rake db:setup RAILS_ENV=production --trace || exit 1; } \
|| { sudo -u git -H bundle exec rake db:migrate RAILS_ENV=production --trace || exit 1; }

cp -pf /home/git/gitlab/VERSION /home/git/data/tmp/

/etc/init.d/gitlab start || exit 1
/usr/sbin/nginx

set +x

while [ 0 ];do sleep 3600;done
