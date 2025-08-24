#!/bin/bash

mkdir -p /var/www/backup

source /etc/environment

cd /var/www/backup

DATE=$(date +"%Y%m%d%H%M")

DATABASES=(ieducar idiario idiario_production)

# MINSIZE is 1 KB
MINSIZE=1000

for db in ${DATABASES[@]}
do
    echo $db

    [[ $db = ieducar* ]] && USER=ieducar || USER=idiario

    FILE="$DATE-$db"

    echo 'gerando arquivos de backup'
    PWD_VARNAME="DB_PASSWORD_${USER^^}"
    PGPASSWORD="${!PWD_VARNAME}" pg_dump -U $USER -h localhost $db -p $DB_PORT --no-acl > "$FILE.sql"

    echo 'compactando arquivos de backup'
    zip "$FILE.zip" "$FILE.sql"

    # Get file size
    FILESIZE=$(stat -c%s "$FILE.zip")
    if (( $FILESIZE < $MINSIZE)); then
        echo '--'
        echo "WARNING: arquivo muito pequeno. VERIFIQUE SE HOUVE ERRO"
        echo '--'
        echo ''
        continue
    fi

    echo 'enviando arquivos de backup para o S3'
    aws s3 cp "$FILE.zip" s3://backup.edu/$DOMAIN/

    echo 'removendo arquivos de backup do disco local'
    rm "$FILE.zip" "$FILE.sql"
    echo ''
    
done

echo 'backup finalizado'