El script_11608.pl realiza la descarga de los docuemntos, y los guarada en el ftp. 
Si llamamos al script sin parametros realizara, la descarga completa y guardara en la carpeta logs de la carpeta ftp del proyecto el archivo update.log.
El archivo update.log registra los archivos que se han descargado.
Para actualizar se deberia llamar: 
# perl script update.log 
El archivo update.log sirve para saber que documentos ya fueron decargados.
