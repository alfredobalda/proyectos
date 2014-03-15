#!/usr/bin/env perl
use strict;
use Encode;
use Date::Simple;
use LWP::UserAgent;
use POSIX qw[strftime];
use Carp;
use HTML::Form;
use HTML::Parser;
use Net::FTP;
use Net::FTP::Recursive;
use File::Path;
use File::Copy;
use Cwd;

#####################################################
############### SETS SCRIPT'S PATH###################
my $script_path = $0;
if($script_path =~ /^\//m){
    $script_path =~ s/^(.+)\/.*/$1/g;
    $ENV{'PWD'} = $script_path;
    chdir($ENV{'PWD'});
}
#####################################################

###################GLOBAL VAR########################
my $P_bulk_api_version = "0.1";
my $P_project_name = "tribunales_tributarios_aduaneros_CL_11608";
my $P_source = "";
my $P_source_url = "http://www.tta.cl/opensite_20110708155435.aspx";
my $P_source_id = "11608";
my $P_content_provider = "Alfredo Horacio Balda";
my $P_content_provider_email = "alfredohbalda\@gmail.com";

my $datapath = "/mnt/mnt/".$P_project_name;
# my $datapath = "$ENV{'PWD'}";
my $scriptpath = "$ENV{'PWD'}";
my $tmppath = "/mnt/mnt/".$P_project_name;

my %hash_document_type;

my $browser = LWP::UserAgent->new;
print "Modo de uso full download: script_11608.pl\n";
print "       Descarga full, guarda listado archivos descargados en logs/update.log  \n";
print "Modo de uso update: script_11608.pl filename_update.log\n";

my %hash_docum;
my $delivery_type = "";
my $nombre_archivo_update;

   mkdir( $datapath );


if (defined $ARGV[0]) {

   # rmtree( $datapath, 1, 1); # vacia la carpeta tmp del proyecto
   # No vacia la carpeta temporal para seguir si ya habia descargdo alguna parte

   $datapath .= "/updates/".strftime('%Y-%m-%d',localtime) if (defined $ARGV[0]);
   mkdir( $datapath );
   $delivery_type = "update";
   $nombre_archivo_update = $ARGV[0];
   print $nombre_archivo_update."<<<<< \n"; 
   open FILE, '<', $nombre_archivo_update or die("No se puede abrir el archivo\n");
   my $linea;
   while ( $linea = <FILE> ) {
    chomp($linea); 
    $hash_docum{$linea} = $linea;
   } 
   close FILE;
  }
else{

   $datapath .= "/initial_dump";
   mkdir( $datapath );
   #$ARGV[0] = $tmppath."/logs/update.log";
   $ARGV[0] = "update.log";
   mkdir( $tmppath."/logs" );
   $delivery_type = "initial_dump";
   $nombre_archivo_update = $ARGV[0];
   if ( open FILE, '<', $nombre_archivo_update ) { 
    my $linea;
    while ( $linea = <FILE> ) {
     chomp($linea); 
     $hash_docum{$linea} = $linea;
    } 
    close FILE;
   }
   #my $linea = '';
   #open(LECTURA,"> ".$nombre_archivo_update) || die "No pudo abrirse: $!";
   #print LECTURA $linea;
   #close(LECTURA);
  }


# datos FTP
my $destserv="174.129.4.65";
my $destuser="alfredobalda";
my $destpass="5y2scG3iWg9p";

my $cantDocumentos = 0;
my $nombre_archivo_tipodoc;
main();

sub main{
   # Corregir que use el DOCTYPE.DAT del temporal si se llama el full update
   my $ftp = Net::FTP->new($destserv) or die "Imposible conectar al servidor FTP $destserv\n";
   $ftp->login($destuser,$destpass) or die("..fallo en la autenticación $!");
   $ftp->mkdir($P_project_name); # make sure the directory exists 
   $ftp->cwd($P_project_name);
   $nombre_archivo_tipodoc = 'DOCTYPE.DAT';
   #$nombre_archivo_tipodoc := $tmppath."/src/DOCTYPE.DAT";
   mkdir( $tmppath."/src" );
   $ftp->get('./src/DOCTYPE.DAT',$nombre_archivo_tipodoc); 
   $ftp->quit(); 

   open(LECTURA,">> ".$nombre_archivo_update) || die "No pudo abrirse: $!";
        
   if ( open(DOCTYPE,"<".$nombre_archivo_tipodoc) ) {
       my $linea;
       while ( $linea = <DOCTYPE> ) {
           chomp($linea); 
	   my @campo = split(";;",$linea);
           $hash_document_type{$campo[0]} = $campo[1];
       } 
       close(DOCTYPE);
   }
   else {
       my $linea = '';
       open(DOCTYPE,">".$nombre_archivo_tipodoc);
       print DOCTYPE $linea;
       close(DOCTYPE);
   }
   $nombre_archivo_update = $ARGV[0];
   mkdir( $tmppath."/logs" );
   descarga();
}


sub descarga{
	print "\n";
	my %params = @_;
	my $response = $browser->get("http://portal.tta.cl/jurisprudencia/index");
	my $contenido = $response->content;

	$cantDocumentos = 0;

	for(my $i= 1;$i<=19;$i++){
	   if ( $i != 5 ){
		my $URL_Seccion = "http://portal.tta.cl/jurisprudencia/rescatarDatos?s=&p=&m=&sm=&fd=&fh=&ru=&ri=&c=&e=&co=&tr=".$i."&est=";
		my $response_nv2 = $browser->get($URL_Seccion);

		# print $URL_Seccion;
        	my $contenido_nv2 = $response_nv2->content;
		$contenido_nv2 =~ s/(<tr)/##corte##$1/isg;
		my @documentos = split(/##corte##/is,$contenido_nv2);
		shift @documentos;

		for(my $k = 1; $k<=$#documentos;$k++){
		
			my %hash;
        		$documentos[$k] =~ s/(<td)/##corteB##$1/isg;
			my @datos = split(/##corteB##/is,$documentos[$k]);

			shift @datos;
			$hash{service} = limpiar_campo($1) if $datos[1] =~ /<td>(.*)<\/td>/is;
			$hash{process_type} = limpiar_campo($1) if $datos[4] =~ /<td>(.*)<\/td>/is;
			$hash{issuer} = limpiar_campo($1) if $datos[2] =~ /<td>(.*)<\/td>/is;			
			$hash{term_date} = limpiar_campo($1) if $datos[3] =~ /<td>(.*)<\/td>/is;

			# fecha que determina el nombre de la carpeta
			#my $dir = "$datapath/documents/$3-$2-$1/" if $hash{term_date} =~ /(\d{2})\/(\d{2})\/(\d{4})/is;
			$hash{resolution_type} = limpiar_campo($1) if $datos[6] =~ /<td>(.*)<\/td>/is;
			$hash{caratula} = limpiar_campo($1) if $datos[7] =~ /<td>(.*)<\/td>/is;
			$hash{categories} = limpiar_campo($1) if $datos[8] =~ /<td>(.*)<\/td>/is;
			$hash{subcategories} = limpiar_campo($1) if $datos[9] =~ /<td>(.*)<\/td>/is;
			
			my $idFicha = $1 if $datos[8] =~ /cargaFicha\('(.*?)'\)/is;
			my $URL_Ficha = "http://portal.tta.cl/jurisprudencia/verFicha?id=$idFicha";
			print "http://portal.tta.cl/jurisprudencia/verFicha?id=$idFicha\n";
#------------------------------------ Entra a la ficha del documento --------------------------------------------
			my $response_nv3 = $browser->get($URL_Ficha);
			my $contenido_nv3 = $response_nv3->content;

			$contenido_nv3 =~ s/(<table)/##corteT##$1/isg;
			my @tablas = split(/##corteT##/is,$contenido_nv3);
			shift @tablas;				
			
			$tablas[0] =~ s/(<tr)/##corteC##$1/isg;	
			#print $tablas[0];
			my @filasFicha = split(/##corteC##/is,$tablas[0]);
       			shift @filasFicha;
			#print "largo: ".$#filasFicha."\n";			
       	     		for(my $m = 0; $m<= $#filasFicha;$m++){
			    if ($filasFicha[$m] =~ /<td class='egovNegro'>RUC<\/td>/isg) {
				$hash{ruc} = limpiar_campo($1) if $filasFicha[$m] =~ /<p class='egovTxtNegro'>(.*?)<\/p>/is;
			    }
			    if ($filasFicha[$m] =~ /<td class='egovNegro'>RIT<\/td>/isg ) {
				$hash{rit} = limpiar_campo($1) if $filasFicha[$m] =~ /<p class='egovTxtNegro'>(.*)<\/p>/is;
			    }				
			    if ($filasFicha[$m] =~ /<td class='egovNegro'>Etiquetas<\/td>/isg) {
				$hash{title} = limpiar_campo($1) if $filasFicha[$m] =~ /<td><p class='egovTxtNegro'>(.*)<\/p>/is;
			    }
			    if ($filasFicha[$m] =~ /<td class='egovNegro'>Extracto<\/td>/isg ) {
				$hash{abstract} = limpiar_campo($1) if $filasFicha[$m] =~ /<p class='egovTxtNegro'>(.*)<\/p>/is;
			    }
			}
			
			$tablas[1] =~ s/(<tr>)/##corteC##$1/isg;
       			my @filasFicha2 = split(/##corteC##/is,$tablas[1]);
        		shift @filasFicha2;			

       			for(my $n = 1; $n<= $#filasFicha2;$n++){
			    my %hashCompleto;
			    #print $n." - ".$filasFicha2[$n]."\n";	
			    if ($filasFicha2[$n] =~ /.pdf/isg) { 	
                                #print $filasFicha2[$n].$n." <<<< ddddddddddd \n";
				$filasFicha2[$n] =~ s/(<td>)/##corteF##$1/isg;
       		 		my @recorroFila = split(/##corteF##/is,$filasFicha2[$n]);
       		 		shift @recorroFila;			
       		 		
				$hashCompleto{document_date} = limpiar_campo($1) if $recorroFila[0] =~ /<td>(.*)<\/td>/is;
				$hashCompleto{document_type} = limpiar_campo($1) if $recorroFila[1] =~ /<td>(.*)<\/td>/is;
				field_cargar(field => "document_type", value => $hashCompleto{document_type});
				    
				my $nombreArchivo = limpiar_campo($1) if $recorroFila[2] =~ /<td>(.*.pdf)<\/td>/is;
				my $nombreArch = limpiar_campo($1) if $recorroFila[2] =~ /<td>(.*).pdf<\/td>/is;
				# $nombreArch ===> $DOCUMENT_ID				

				my $DOCUMENT_ID = $1 if $recorroFila[3] =~ /onclick="descargaDoc\('(.*?)'\)"/is;
				$hashCompleto{document_name} = $DOCUMENT_ID;
				$hashCompleto{link_pdf} = 'http://portal.tta.cl/jurisprudencia/download?id='.$DOCUMENT_ID;

				#$hashCompleto{adjunto} = extraer_pdf(url => $hashComleto{link_pdf}, fecha => $params{fecha}, nombre => $hashCompleto{texto1});
				if (not exists $hash_docum{$DOCUMENT_ID}){
              		            $hashCompleto{adjunto} = extraer_pdf(url => $hashCompleto{link_pdf}, fecha => $hash{term_date}, nombre => $DOCUMENT_ID);
				    $hashCompleto{service} = $hash{service};
				    $hashCompleto{process_type} = $hash{process_type};
				    $hashCompleto{issuer} = $hash{issuer};
				    $hashCompleto{term_date} = $hash{term_date};
				    
				    $hashCompleto{resolution_type} = $hash{resolution_type};
				    $hashCompleto{caratula} = $hash{caratula};
				    $hashCompleto{categories} = $hash{categories};
			            $hashCompleto{subcategories} = $hash{subcategories};
				    $hashCompleto{ruc} = $hash{ruc};
				    $hashCompleto{rit} = $hash{rit};
				    $hashCompleto{title} = $hash{title};
				    $hashCompleto{abstract} = $hash{abstract};
				
				    my $nombre_xml = "$datapath/documents/$3-$2-$1/$DOCUMENT_ID/" if $hash{term_date} =~ /(\d{2})\/(\d{2})\/(\d{4})/is;
                        	    $nombre_xml.= "METADATA­-".$DOCUMENT_ID.".xml";
        	       		    my $xml = armar_xml(%hashCompleto);
				    settextofile($xml,">$nombre_xml");
	     	                    print "Tribunal: ".$hash{issuer}."\n";
				    print "Fecha: ".$hashCompleto{term_date}."\n";
				    print "RUC: ".$hash{ruc}."\n";
				    print "RIT: ".$hash{rit}."\n";
				    print "Documento: ".$hashCompleto{document_name}."\n";
				    print "Fecha Doc.: ".$hashCompleto{document_date}."\n";
				    $cantDocumentos = $cantDocumentos + 1; 
				    cargar_doc_al_archivo(documento => $DOCUMENT_ID);
				    #%hash_docum{$DOCUMENT_ID} = $DOCUMENT_ID;
				}
				else{
				    print $hash_docum{$DOCUMENT_ID}." <- documento ya bajado.\n";
     		                }
				print "------------------------------------------------------------------------------\n"; 
			    }
			}
        	}
            }
	}
#armar INFO.xml   
	my $INFOxml = armar_INFO_xml();
	settextofile($INFOxml,">INFO.xml");

	my $salida = $datapath."/COMPLETED";
	open (SALIDA,"+>$salida") || die "ERROR: No puedo abrir el fichero $salida\n";
	close (SALIDA);
        copy($nombre_archivo_tipodoc,$tmppath."/src/");
        copy($nombre_archivo_update,$tmppath."/logs/");	
# copiar de /mnt/mnt/ al ftp
        print "Copiando al ftp ...";
        my $ftp = Net::FTP::Recursive->new($destserv, Debug => 0);
        $ftp->login($destuser,$destpass);
        $ftp->cwd($P_project_name);
        my $orig_dir = getcwd();
# cambio el path corriente por el tmp
        chdir($tmppath) or die(" No puede abrir el directorio $tmppath $!");
        $ftp->binary;
        $ftp->rput();
        $ftp->quit;
        chdir($orig_dir);

# borrar los temporales
        print " OK.\n";
        print "Borrando archivos temporales...";
        rmtree( $tmppath, 1, 1); # vacia la carpeta tmp del proyecto
        print " OK.\n";
        
	print "COMPLETED\n";
}

sub field_cargar{
 	my %params = @_;
        #@keys = keys %data;
        #$size = @keys;my $keys
        #$hash_document_type{keys %hash_document_type} = $params{value};
        if (not exists $hash_document_type{$params{value}}){
		$hash_document_type{$params{value}} = keys %hash_document_type;
		open(DOCTYPE,">> ".$nombre_archivo_tipodoc) || die "No pudo abrirse: $!";
		print DOCTYPE $params{value}.";;".$hash_document_type{$params{value}}."\n";
		close(DOCTYPE);
	}
}				

sub cargar_doc_al_archivo{
	my %params = @_;
	#open(LECTURA,">> ".$datapath."/".$nombre_archivo_update) || die "No pudo abrirse: $!";
	open(LECTURA,">> ".$nombre_archivo_update) || die "No pudo abrirse: $!";
        print LECTURA $params{documento}."\n";
	close(LECTURA);
}

sub fecha_valida{
	my %params = @_;
	return 0 if $params{fecha} !~ /\d{4}-\d{2}-\d{2}/is && $params{fecha} !~ /\d{2}\/\d{2}\/\d{4}/is;    
	$params{fecha} = "$3-$2-$1" if $params{fecha} =~ /(\d{2})\/(\d{2})\/(\d{4})/is;
	my $tmp = Date::Simple->new($params{fecha});
	return ($tmp eq $params{fecha});    
}

sub limpiar_campo{
	my $campo = $_[0];
	$campo =~s/<[^>]+>//isg;    
	$campo =~s/[\r\n]+//isg;
	$campo =~s/\t/ /isg;
	$campo =~s/ {2,}/ /isg;
	$campo =~s/^ //isg;
	$campo =~s/ $//isg;
	return $campo;
};

sub extraer_pdf{
    my %params = @_;
    my $nombre = "$datapath/documents/$3-$2-$1/$params{nombre}/contents" if $params{fecha} =~ /(\d{2})\/(\d{2})\/(\d{4})/is;

    #print $params{fecha}."<<< Fecha\n";
    #print $params{nombre}."<<< Nombre\n";
    #print $params{url}."<<< URL\n";

    `mkdir -p $nombre`;
    
    my $nombreTXT = $nombre."/".$params{nombre}.".txt";
    my $nombreHTML = $nombre."/".$params{nombre}.".html";
    $nombre.= "/".$params{nombre}.".pdf";

    #$browser->mirror($params{url},$nombre);
    `wget $params{url} -O $nombre`;

    `pdftotext $nombre $nombreTXT`;
    `pdftohtml $nombre $nombreHTML`;
    
    return $nombre if -e $nombre;
    return undef;
}

sub process_table{
    my ($table_data, $b_clean_linefeeds) = @_;
    if(!$b_clean_linefeeds){
        $table_data =~ s/[\r\n]+/----SALTODELINEA----/g;
    }
    $table_data =~ s/[\r\n]+//g;
    $table_data =~ s/([\t ])[\t ]+/$1/g;
    $table_data =~ s/<hr>/---HR---/ig;
    $table_data =~ s/<td[^>]*>/---BTD---/gi;
    $table_data =~ s/<\/th>/---ETH---/gi;
    $table_data =~ s/<th[^>]*>/---BTH---/gi;
    $table_data =~ s/<\/td>/---ETD---/gi;
    $table_data =~ s/<tr[^>]*>/---BTR---/gi;
    $table_data =~ s/<\/tr>/---ETR---/gi;
    $table_data =~ s/<ul>/---BUL---/gi;
    $table_data =~ s/<\/ul>/---EUL---/gi;
    $table_data =~ s/<li>/---BLI---/gi;
    $table_data =~ s/<\/li>/---ELI---/gi;
    $table_data =~ s/<img([^>]+)>/---IMG---$1---/gi;
    $table_data =~ s/<br>/\n/gi;
    $table_data =~ s/<[^>]+>//gi;
    $table_data =~ s/---IMG---(.*?)---/<img$1>/gi;
    $table_data =~ s/---HR---/<hr>/ig;
    $table_data =~ s/---BTD---/<td>/gi;
    $table_data =~ s/---ETD---/<\/td>/gi;
    $table_data =~ s/---BTR---/<tr>/gi;
    $table_data =~ s/---ETR---/<\/tr>/gi;
    $table_data =~ s/---BTH---/<th>/gi;
    $table_data =~ s/---ETH---/<\/th>/gi;
    $table_data =~ s/---BUL---/<ul>/gi;
    $table_data =~ s/---EUL---/<\/ul>/gi;
    $table_data =~ s/---BLI---/<li>/gi;
    $table_data =~ s/---ELI---/<\/li>/gi;
    $table_data =~ s/(?<=>)[\r\n]*([^<\r\n]+)[\r\n]*(?=<)/$1/g;
    $table_data =~ s/td>[\r\n]+<td/td><td/g;
    $table_data =~ s/<tr>([\r\n\t ]*<\/?td>[\r\n\t ]*)+?(?=<tr>)//gi;
    $table_data =~ s/<tr>([\r\n\t ]*<\/?td>[\r\n\t ]*)+?<\/tr>//gi;
    if(!$b_clean_linefeeds){
        $table_data =~ s/----SALTODELINEA----/\n/g;
        $table_data =~ s/>[\r\n]+/>/g;
    }
    else{
        $table_data =~ s/----SALTODELINEA----//g;
    }
    return $table_data;
}

sub process_tables{
    my (%in) = @_;
    my $text = $in{'texto'};
    my $b_clean_linefeeds = $in{'clean_lf'} if($in{'clean_lf'});

    if(defined $in{'clean_useless_tags'} && $in{'clean_useless_tags'} eq 'si'){
#        log_msj("LIMPIO LOS TAGS INÚTILES");
        $text = clean_useless_tags($text);
    }

    my %tables = ();
    my $pila_tabla = 0;
    my $trash_var = $text;
    while($trash_var =~ /(<table.*?>|<\/table>)/ig){
        my $tag = $1;
        if($tag =~ /<table.*?>/i){
            $pila_tabla++;
            $text =~ s/$tag/<table $pila_tabla>/i;
        }
        else{
            $text =~ /<table $pila_tabla>(.*?)<\/table>/si;
            my $data = $1;
            my $table_data = process_table($data, $b_clean_linefeeds);
            $text =~ s/<table $pila_tabla>.*?<\/table>/\n<table border class="tabla_texto_libre">$table_data<\/table>\n/si;
            $pila_tabla--;
        }
    }
    return $text;
}

sub armar_xml{
    my %hash=@_;
    my $xml='';
    foreach my $key (keys %hash){
        if (length($hash{$key})<1500){
            $xml="<$key>$hash{$key}</$key>\n".$xml; #La idea de esto es mandar los textos (NOT,MTG,etc) al final par no mezclararlos con los demas campos y así verlos mas fácil.
        }else{
            $xml.="<$key>$hash{$key}</$key>\n";
        }
    }
    $xml = "<document>\n".$xml;
    $xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n".$xml;
    $xml.= "</document>\n";
    
    return $xml;
}

sub armar_INFO_xml{
    my %hash=@_;
    my $xml='';
    $xml .= "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";
    $xml .= "<config>\n";
    $xml .= "<bulk_api_version>1.00</api_version>\n";
    $xml .= "<deliveri_type>".$delivery_type."</delivery_type>\n";
    $xml .= "<project_name>".$P_project_name."</project_name>\n";
    $xml .= "<source>".$P_source."</source>\n";
    $xml .= "<source_url>".$P_source_url."</source_url>\n";
    $xml .= "<documents>".$cantDocumentos."</documents>\n";
    $xml .= "<content_provider>".$P_content_provider."</content_provider>\n";
    $xml .= "<content_provider_email>".$P_content_provider_email."</content_email>\n";
    $xml .= "<source_id>".$P_source_id."</source_id>\n";
    $xml .= "<fields>\n";
    $xml .= "<field name=\"service\" type=\"list\">\n";
    $xml .= "<valid_value value_id=\"0\" value_description=\"Servicio de Impuestos Internos\"/>\n";
    $xml .= "<valid_value value_id=\"1\" value_description=\"Servicio Nacional de Aduanas\"/>\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"process_type\" type=\"dependent_list\" depends_on=\"service\">\n";
    $xml .= "<valid_value value_id=\"5\" value_description=\"Procedimiento general de reclamación\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"6\" value_description=\"Procedimiento de reclamo de los avalúos de BBRR\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"7\" value_description=\"Procedimiento de reclamación por vulneración de derechos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"8\" value_description=\"Procedimiento general para la aplicación de sanciones\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"9\" value_description=\"Procedimiento especial de aplicación de ciertas multas\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"10\" value_description=\"Especial Secreto Bancario\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"0\" value_description=\"Procedimiento general de reclamación\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"1\" value_description=\"Procedimiento especial por vulneración de derechos\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"2\" value_description=\"Procedimiento de reclamo de multas por infracciones\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"3\" value_description=\"Procedimiento de reclamo contra sanciones disciplinarias\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"4\" value_description=\"Procedimiento artículo 199 OA\" parent_field_id=\"1\" />\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"issuer\" type=\"list\">\n";
    $xml .= "<valid_value value_id=\"6\" value_description=\"Tribunal de Coquimbo\"/>\n";
    $xml .= "<valid_value value_id=\"7\" value_description=\"Tribunal del Maule\"/>\n";
    $xml .= "<valid_value value_id=\"8\" value_description=\"Tribunal de la Araucanía\"/>\n";
    $xml .= "<valid_value value_id=\"9\" value_description=\"Tribunal de Magallanes y Antártica Chilena\"/>\n";
    $xml .= "<valid_value value_id=\"1\" value_description=\"Tribunal Arica y Parinacota\"/>\n";
    $xml .= "<valid_value value_id=\"2\" value_description=\"Tribunal Tarapacá\"/>\n";
    $xml .= "<valid_value value_id=\"3\" value_description=\"Tribunal Antofagasta\"/>\n";
    $xml .= "<valid_value value_id=\"4\" value_description=\"Tribunal Atacama\"/>\n";
    $xml .= "<valid_value value_id=\"10\" value_description=\"Tribunal del Biobio\"/>\n";
    $xml .= "<valid_value value_id=\"11\" value_description=\"Tribunal  de los Rios\"/>\n";
    $xml .= "<valid_value value_id=\"12\" value_description=\"Tribunal de los Lagos\"/>\n";
    $xml .= "<valid_value value_id=\"13\" value_description=\"Tribunal de Aysen\"/>\n";
    $xml .= "<valid_value value_id=\"14\" value_description=\"Tribunal de Valparaiso\"/>\n";
    $xml .= "<valid_value value_id=\"15\" value_description=\"Tribunal R. Metropolitana. Primero\"/>\n";
    $xml .= "<valid_value value_id=\"16\" value_description=\"Tribunal R. Metropolitana. Segundo\"/>\n";
    $xml .= "<valid_value value_id=\"17\" value_description=\"Tribunal R. Metropolitana. Tercero\"/>\n";
    $xml .= "<valid_value value_id=\"18\" value_description=\"Tribunal R. Metropolitana. Cuarto\"/>\n";
    $xml .= "<valid_value value_id=\"19\" value_description=\"Tribunal L.G.B. Ohiggins\"/>\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"term_date\" type=\"date\" />\n";
    $xml .= "<field name=\"document_date\" type=\"date\" />\n";
    $xml .= "<field name=\"resolution_type\" type=\"list\">\n";
    $xml .= "<valid_value value_id=\"01\" value_description=\"Fallada\" />\n";
    $xml .= "<valid_value value_id=\"02\" value_description=\"Inadmisible\" />\n";
    $xml .= "<valid_value value_id=\"03\" value_description=\"Desistida\" />\n";
    $xml .= "<valid_value value_id=\"04\" value_description=\"No presentada\" />\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"caratula\" type=\"string\" />\n";
    $xml .= "<field name=\"categories\" type=\"list\" >\n";
    $xml .= "<valid_value value_id=\"0\" value_description=\"Liquidaciones\"/>\n";
    $xml .= "<valid_value value_id=\"1\" value_description=\"Cargos\"/>\n";
    $xml .= "<valid_value value_id=\"2\" value_description=\"Otras actuaciones base tributos\"/>\n";
    $xml .= "<valid_value value_id=\"3\" value_description=\"Exportación\"/>\n";
    $xml .= "<valid_value value_id=\"4\" value_description=\"Devolución administrativa de derechos\"/>\n";
    $xml .= "<valid_value value_id=\"5\" value_description=\"Las demás que establezca la ley\"/>\n";
    $xml .= "<valid_value value_id=\"6\" value_description=\"Artículo 19 Nº 21 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"7\" value_description=\"Artículo 19 Nº 22 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"8\" value_description=\"Artículo 19 Nº 24 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"9\" value_description=\"Artículo 173 OA\"/>\n";
    $xml .= "<valid_value value_id=\"10\" value_description=\"Artículo 174 OA\"/>\n";
    $xml .= "<valid_value value_id=\"11\" value_description=\"Artículo 175 OA\"/>\n";
    $xml .= "<valid_value value_id=\"12\" value_description=\"Artículo 176 OA\"/>\n";
    $xml .= "<valid_value value_id=\"13\" value_description=\"Artículo 23 Decreto Hacienda 329/79 \"/>\n";
    $xml .= "<valid_value value_id=\"14\" value_description=\"Infracciones ley de Ozono\"/>\n";
    $xml .= "<valid_value value_id=\"15\" value_description=\"Suspensión\"/>\n";
    $xml .= "<valid_value value_id=\"16\" value_description=\"Cancelación\"/>\n";
    $xml .= "<valid_value value_id=\"17\" value_description=\"Inciso tercero artículo 199\"/>\n";
    $xml .= "<valid_value value_id=\"18\" value_description=\"Liquidación\"/>\n";
    $xml .= "<valid_value value_id=\"19\" value_description=\"Giro\"/>\n";
    $xml .= "<valid_value value_id=\"20\" value_description=\"Pago\"/>\n";
    $xml .= "<valid_value value_id=\"21\" value_description=\"Resolución\"/>\n";
    $xml .= "<valid_value value_id=\"22\" value_description=\"Resolución que deniegue  peticiones del art. 126 CT\"/>\n";
    $xml .= "<valid_value value_id=\"23\" value_description=\"Tasación art. 64, inc. 6to. del CT\"/>\n";
    $xml .= "<valid_value value_id=\"24\" value_description=\"Artículo 97 Nº 2 (siempre que se reclame conjuntamente con el impuesto)\"/>\n";
    $xml .= "<valid_value value_id=\"25\" value_description=\"Artículo 97 Nº 11 (siempre que se reclame conjuntamente con el impuesto)\"/>\n";
    $xml .= "<valid_value value_id=\"26\" value_description=\"Tasación general bien raíz agrícola \"/>\n";
    $xml .= "<valid_value value_id=\"27\" value_description=\"Tasación general bien raíz no agrícola\"/>\n";
    $xml .= "<valid_value value_id=\"28\" value_description=\"Modificación individual de avalúo bien raíz agrícola \"/>\n";
    $xml .= "<valid_value value_id=\"29\" value_description=\"Modificación individual de avalúo bien raíz no agrícola\"/>\n";
    $xml .= "<valid_value value_id=\"30\" value_description=\"Artículo 19 N° 21 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"31\" value_description=\"Artículo 19 Nº 22 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"32\" value_description=\"Artículo 19 Nº 24 CPR\"/>\n";
    $xml .= "<valid_value value_id=\"33\" value_description=\"Artículo 30 inciso 5° del CT\"/>\n";
    $xml .= "<valid_value value_id=\"34\" value_description=\"Artículo 97 N° 4 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"35\" value_description=\"Artículo 97 N° 5 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"36\" value_description=\"Artículo 97 N° 8 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"37\" value_description=\"Artículo 97 N° 10 inciso 3° del CT\"/>\n";
    $xml .= "<valid_value value_id=\"38\" value_description=\"Artículo 97 N° 9 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"39\" value_description=\"Artículo 97 N° 12 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"40\" value_description=\"Artículo  97 N° 13 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"41\" value_description=\"Artículo 97 N° 14 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"42\" value_description=\"Artículo 97 N° 18 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"43\" value_description=\"Artículo 97 N° 22 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"44\" value_description=\"Artículo 97 N° 23 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"45\" value_description=\"Artículo 97 N° 25 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"46\" value_description=\"Artículo 97 N° 26 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"47\" value_description=\"Artículo 100 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"48\" value_description=\"Artículo 64 Ley 16.271\"/>\n";
    $xml .= "<valid_value value_id=\"49\" value_description=\"Artículo 90 inc. 3°, LIR\"/>\n";
    $xml .= "<valid_value value_id=\"50\" value_description=\"Artículo 97 N° 16 Inciso 3° del CT\"/>\n";
    $xml .= "<valid_value value_id=\"51\" value_description=\"Artículo 97 Inciso 6º LIR\"/>\n";
    $xml .= "<valid_value value_id=\"52\" value_description=\"Artículo 102 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"53\" value_description=\"Artículo 103 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"54\" value_description=\"Artículo 104 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"55\" value_description=\"Artículo 27 BIS, Inc. 5, Ley IVA\"/>\n";
    $xml .= "<valid_value value_id=\"56\" value_description=\"Artículo 97 N° 1 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"57\" value_description=\"Artículo 97 N° 2 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"58\" value_description=\"Artículo 97 N° 11del CT\"/>\n";
    $xml .= "<valid_value value_id=\"59\" value_description=\"Artículo 97 N° 3 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"60\" value_description=\"Artículo 97 N° 6 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"61\" value_description=\"Artículo 97 N° 7 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"62\" value_description=\"Artículo 97 N° 10 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"63\" value_description=\"Artículo 97 N° 15 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"64\" value_description=\"Artículo 97 N° 16 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"65\" value_description=\"Artículo 97 N° 17 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"66\" value_description=\"Artículo 97 N° 19 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"67\" value_description=\"Artículo 97 N° 20 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"68\" value_description=\"Artículo 97 N° 21 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"69\" value_description=\"Artículo 109 del CT\"/>\n";
    $xml .= "<valid_value value_id=\"72\" value_description=\"Artículo 8 bis CT\"/>\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"subcategories\" type=\"dependent_list\" depends_on=\"categories\">\n";
    $xml .= "<valid_value value_id=\"119\" value_description=\"Impuesto a las donaciones\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"52\" value_description=\"Renta Imp. 1ª  Cat. Subdeclaración u omisión de ingresos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"53\" value_description=\"Renta Imp. 1ª  Cat. Reconocimiento costo que no corresponde\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"54\" value_description=\"Renta Imp. 1ª  Cat. Gastos rechazados. Primera categoría.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"55\" value_description=\"Renta Imp. 1ª  Cat. gastos rechazados. Art. 21 LIR.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"56\" value_description=\"Renta Imp. 1ª Cat. Subdeclaración retiros art. 14 bis LIR.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"57\" value_description=\"Renta Imp. G.C. No presentación declaración.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"58\" value_description=\"Renta Imp. G.C. No presentación dec. conjunta cónyuges.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"59\" value_description=\"Renta Imp. G.C. presentación declaración incompleta\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"60\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto 1ª Cat.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"61\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto Territorial\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"62\" value_description=\"Renta Imp. G.C. Declaración errónea Cotizaciones previsionales\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"63\" value_description=\"Renta Imp. G.C. Declaración errónea. Base imponible. Sumatoria\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"64\" value_description=\"Renta Imp. G.C. Declaración errónea. Imp. Único 2ª Cat\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"65\" value_description=\"Renta Imp. G.C. Dec. errónea. Crédito proporcional rentas exentas\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"66\" value_description=\"Renta Imp. G.C. Declaración errónea.Otro crédito\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"67\" value_description=\"Renta Imp. G.C. Dec. errónea. Cálculo incorrecto del impuesto\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"68\" value_description=\"Renta Imp. G.C. Declaración errónea. Art. 57 bis LIR \" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"69\" value_description=\"Renta Imp. G.C. Declaración errónea. APV o Art. 42 bis LIR\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"70\" value_description=\"Renta Imp. G.C. Dec. errónea. Retenciones Art. 42 N° 2 LIR\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"71\" value_description=\"Renta Imp. G.C. Dec. errónea. Créditos socios o comuneros\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"72\" value_description=\"Renta Imp. G.C. Dec. errónea. Reliquidación por Término giro\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"73\" value_description=\"Renta Impuesto Adicional. Marcas, patentes y otros\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"74\" value_description=\"Renta Imp. Adicional. Patentes de invención, de modelos de utilidad\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"75\" value_description=\"Renta Imp. Adicional. Programas computacionales\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"76\" value_description=\"Renta Imp. Adicional. Regalías o asesorias improductivas\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"77\" value_description=\"Renta Imp. Adicional. Materiales de cine o televisón\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"78\" value_description=\"Renta Imp. Adicional. Derecho de edición o de autor\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"79\" value_description=\"Renta Imp. Adicional. Intereses\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"80\" value_description=\"Renta Imp. Adicional. Depósitos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"81\" value_description=\"Renta Imp. Adicional. Créditos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"82\" value_description=\"Renta Imp. Adicional. Saldos de precio\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"83\" value_description=\"Renta Imp. Adicional. Bonos o debentures\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"84\" value_description=\"Renta Imp. Adicional. Aceptaciones bancarias latinoamer.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"85\" value_description=\"Renta Imp. Adicional. Instrumentos deuda pública. Art.104 LIR.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"86\" value_description=\"Renta Imp. Adicional. Remuneraciones servicios en el extranjero\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"87\" value_description=\"Renta Imp. Adicional. Primas de Serguro\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"88\" value_description=\"Renta Imp. Adicional. Fletes marítimos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"89\" value_description=\"Renta Imp. Adicional. Uso o goce temporal naves extranjeras\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"90\" value_description=\"Renta Imp. Adicional. Art.59 N° 6 LIR\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"91\" value_description=\"Renta Imp. Adicional. Art. 60 LIR\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"92\" value_description=\"Renta Imp. Adicional. Chilenos no residentes ni domiciliados en Chile\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"93\" value_description=\"Renta Impuesto único a los premios de loteria\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"94\" value_description=\"Renta Impuesto único de Primera Categoría\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"95\" value_description=\"Renta Impuesto único de Sergunda Categoría\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"96\" value_description=\"Iva-Ventas. Hecho gravado general\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"97\" value_description=\"Iva-Ventas. Artículo 8) Letra a)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"98\" value_description=\"Iva-Ventas. Artículo 8) Letra b)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"99\" value_description=\"Iva-Ventas. Artículo 8) Letra c)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"100\" value_description=\"Iva-Ventas. Artículo 8) Letra d)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"101\" value_description=\"Iva-Ventas. Artículo 8) Letra e)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"102\" value_description=\"Iva-Ventas. Artículo 8) Letra f)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"103\" value_description=\"Iva-Ventas. Artículo 8) Letra k)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"104\" value_description=\"Iva-Ventas. Artículo 8) Letra l)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"105\" value_description=\"Iva-Ventas. Artículo 8) Letra m)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"106\" value_description=\"Iva-Servicios. Hecho gravado general\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"107\" value_description=\"Iva-Servicios. Artículo 8 Letra e)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"108\" value_description=\"Iva-Servicios. Artículo 8 Letra g)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"109\" value_description=\"Iva-Servicios. Artículo 8 Letra h)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"110\" value_description=\"Iva-Servicios. Artículo 8 Letra i)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"111\" value_description=\"Iva-Servicios. Artículo 8 Letra j)\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"112\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°1 DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"113\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 1° DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"114\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 3° DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"115\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 4° DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"116\" value_description=\"Impuesto de timbres y estampillas. Artículo 2 DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"117\" value_description=\"Impuesto de timbres y estampillas. Artículo 3 DL N° 3475\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"120\" value_description=\"Impuesto territorial. Sobretasa\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"121\" value_description=\"Impuesto territorial. Exención.\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"122\" value_description=\"Impuesto territorial. Otra\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"2002201201\" value_description=\"Acreditación de origen de fondos\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"2205201201\" value_description=\"Crédito especial IVA de la Construcción\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"118\" value_description=\"Impuesto a la herencia\" parent_field_id=\"0\" />\n";
    $xml .= "<valid_value value_id=\"167\" value_description=\"Iva-Ventas. Hecho gravado general\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"168\" value_description=\"Iva-Ventas. Artículo 8) Letra a)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"170\" value_description=\"Iva-Ventas. Artículo 8) Letra c)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"171\" value_description=\"Iva-Ventas. Artículo 8) Letra d)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"172\" value_description=\"Iva-Ventas. Artículo 8) Letra e)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"173\" value_description=\"Iva-Ventas. Artículo 8) Letra f)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"174\" value_description=\"Iva-Ventas. Artículo 8) Letra k)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"175\" value_description=\"Iva-Ventas. Artículo 8) Letra l)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"176\" value_description=\"Iva-Ventas. Artículo 8) Letra m)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"177\" value_description=\"Iva-Servicios. Hecho gravado general\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"178\" value_description=\"Iva-Servicios. Artículo 8 Letra e)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"179\" value_description=\"Iva-Servicios. Artículo 8 Letra g)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"180\" value_description=\"Iva-Servicios. Artículo 8 Letra h)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"181\" value_description=\"Iva-Servicios. Artículo 8 Letra i)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"182\" value_description=\"Iva-Servicios. Artículo 8 Letra j)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"183\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°1 DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"184\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 1° DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"185\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 3° DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"186\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 4° DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"187\" value_description=\"Impuesto de timbres y estampillas. Artículo 2 DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"188\" value_description=\"Impuesto de timbres y estampillas. Artículo 3 DL N° 3475\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"189\" value_description=\"Impuesto a la herencia\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"190\" value_description=\"Impuesto a las donaciones\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"191\" value_description=\"Impuesto territorial. Sobretasa\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"192\" value_description=\"Impuesto territorial. Exención.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"193\" value_description=\"Impuesto territorial. Otra\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"146\" value_description=\"Renta Imp. Adicional. Programas computacionales\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"169\" value_description=\"Iva-Ventas. Artículo 8) Letra b)\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"123\" value_description=\"Renta Imp. 1ª  Cat. Subdeclaración u omisión de ingresos\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"124\" value_description=\"Renta Imp. 1ª  Cat. Reconocimiento costo que no corresponde\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"125\" value_description=\"Renta Imp. 1ª  Cat. Gastos rechazados. Primera categoría.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"126\" value_description=\"Renta Imp. 1ª  Cat. gastos rechazados. Art. 21 LIR.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"127\" value_description=\"Renta Imp. 1ª Cat. Subdeclaración retiros art. 14 bis LIR.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"128\" value_description=\"Renta Imp. G.C. No presentación declaración.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"129\" value_description=\"Renta Imp. G.C. No presentación dec. conjunta cónyuges.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"130\" value_description=\"Renta Imp. G.C. presentación declaración incompleta\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"131\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto 1ª Cat.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"132\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto Territorial\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"133\" value_description=\"Renta Imp. G.C. Declaración errónea Cotizaciones previsionales\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"134\" value_description=\"Renta Imp. G.C. Declaración errónea. Base imponible. Sumatoria\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"135\" value_description=\"Renta Imp. G.C. Declaración errónea. Imp. Único 2ª Cat\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"136\" value_description=\"Renta Imp. G.C. Dec. errónea. Crédito proporcional rentas exentas\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"137\" value_description=\"Renta Imp. G.C. Declaración errónea.Otro crédito\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"138\" value_description=\"Renta Imp. G.C. Dec. errónea. Cálculo incorrecto del impuesto\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"139\" value_description=\"Renta Imp. G.C. Declaración errónea. Art. 57 bis LIR \" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"140\" value_description=\"Renta Imp. G.C. Declaración errónea. APV o Art. 42 bis LIR\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"141\" value_description=\"Renta Imp. G.C. Dec. errónea. Retenciones Art. 42 N° 2 LIR\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"142\" value_description=\"Renta Imp. G.C. Dec. errónea. Créditos socios o comuneros\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"143\" value_description=\"Renta Imp. G.C. Dec. errónea. Reliquidación por Término giro\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"144\" value_description=\"Renta Impuesto Adicional. Marcas, patentes y otros\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"145\" value_description=\"Renta Imp. Adicional. Patentes de invención, de modelos de utilidad\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"147\" value_description=\"Renta Imp. Adicional. Regalías o asesorias improductivas\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"148\" value_description=\"Renta Imp. Adicional. Materiales de cine o televisón\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"149\" value_description=\"Renta Imp. Adicional. Derecho de edición o de autor\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"150\" value_description=\"Renta Imp. Adicional. Intereses\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"151\" value_description=\"Renta Imp. Adicional. Depósitos\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"152\" value_description=\"Renta Imp. Adicional. Créditos\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"153\" value_description=\"Renta Imp. Adicional. Saldos de precio\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"154\" value_description=\"Renta Imp. Adicional. Bonos o debentures\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"155\" value_description=\"Renta Imp. Adicional. Aceptaciones bancarias latinoamer.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"156\" value_description=\"Renta Imp. Adicional. Instrumentos deuda pública. Art.104 LIR.\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"157\" value_description=\"Renta Imp. Adicional. Remuneraciones servicios en el extranjero\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"158\" value_description=\"Renta Imp. Adicional. Primas de Serguro\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"159\" value_description=\"Renta Imp. Adicional. Fletes marítimos\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"160\" value_description=\"Renta Imp. Adicional. Uso o goce temporal naves extranjeras\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"161\" value_description=\"Renta Imp. Adicional. Art.59 N° 6 LIR\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"162\" value_description=\"Renta Imp. Adicional. Art. 60 LIR\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"163\" value_description=\"Renta Imp. Adicional. Chilenos no residentes ni domiciliados en Chile\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"164\" value_description=\"Renta Impuesto único a los premios de loteria\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"165\" value_description=\"Renta Impuesto único de Primera Categoría\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"166\" value_description=\"Renta Impuesto único de Sergunda Categoría\" parent_field_id=\"19\" />\n";
    $xml .= "<valid_value value_id=\"212\" value_description=\"Renta Imp. G.C. Dec. errónea. Retenciones Art. 42 N° 2 LIR\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"213\" value_description=\"Renta Imp. G.C. Dec. errónea. Créditos socios o comuneros\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"214\" value_description=\"Renta Imp. G.C. Dec. errónea. Reliquidación por Término giro\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"215\" value_description=\"Renta Impuesto Adicional. Marcas, patentes y otros\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"216\" value_description=\"Renta Imp. Adicional. Patentes de invención, de modelos de utilidad\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"217\" value_description=\"Renta Imp. Adicional. Programas computacionales\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"218\" value_description=\"Renta Imp. Adicional. Regalías o asesorias improductivas\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"219\" value_description=\"Renta Imp. Adicional. Materiales de cine o televisón\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"220\" value_description=\"Renta Imp. Adicional. Derecho de edición o de autor\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"221\" value_description=\"Renta Imp. Adicional. Intereses\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"222\" value_description=\"Renta Imp. Adicional. Depósitos\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"223\" value_description=\"Renta Imp. Adicional. Créditos\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"224\" value_description=\"Renta Imp. Adicional. Saldos de precio\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"225\" value_description=\"Renta Imp. Adicional. Bonos o debentures\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"226\" value_description=\"Renta Imp. Adicional. Aceptaciones bancarias latinoamer.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"227\" value_description=\"Renta Imp. Adicional. Instrumentos deuda pública. Art.104 LIR.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"228\" value_description=\"Renta Imp. Adicional. Remuneraciones servicios en el extranjero\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"229\" value_description=\"Renta Imp. Adicional. Primas de Serguro\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"230\" value_description=\"Renta Imp. Adicional. Fletes marítimos\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"231\" value_description=\"Renta Imp. Adicional. Uso o goce temporal naves extranjeras\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"232\" value_description=\"Renta Imp. Adicional. Art.59 N° 6 LIR\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"233\" value_description=\"Renta Imp. Adicional. Art. 60 LIR\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"234\" value_description=\"Renta Imp. Adicional. Chilenos no residentes ni domiciliados en Chile\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"235\" value_description=\"Renta Impuesto único a los premios de loteria\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"236\" value_description=\"Renta Impuesto único de Primera Categoría\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"237\" value_description=\"Renta Impuesto único de Sergunda Categoría\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"238\" value_description=\"Iva-Ventas. Hecho gravado general\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"239\" value_description=\"Iva-Ventas. Artículo 8) Letra a)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"240\" value_description=\"Iva-Ventas. Artículo 8) Letra b)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"241\" value_description=\"Iva-Ventas. Artículo 8) Letra c)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"242\" value_description=\"Iva-Ventas. Artículo 8) Letra d)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"243\" value_description=\"Iva-Ventas. Artículo 8) Letra e)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"244\" value_description=\"Iva-Ventas. Artículo 8) Letra f)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"245\" value_description=\"Iva-Ventas. Artículo 8) Letra k)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"246\" value_description=\"Iva-Ventas. Artículo 8) Letra l)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"247\" value_description=\"Iva-Ventas. Artículo 8) Letra m)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"248\" value_description=\"Iva-Servicios. Hecho gravado general\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"249\" value_description=\"Iva-Servicios. Artículo 8 Letra e)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"250\" value_description=\"Iva-Servicios. Artículo 8 Letra g)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"251\" value_description=\"Iva-Servicios. Artículo 8 Letra h)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"252\" value_description=\"Iva-Servicios. Artículo 8 Letra i)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"253\" value_description=\"Iva-Servicios. Artículo 8 Letra j)\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"254\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°1 DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"255\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 1° DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"256\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 3° DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"194\" value_description=\"Renta Imp. 1ª  Cat. Subdeclaración u omisión de ingresos\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"195\" value_description=\"Renta Imp. 1ª  Cat. Reconocimiento costo que no corresponde\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"196\" value_description=\"Renta Imp. 1ª  Cat. Gastos rechazados. Primera categoría.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"197\" value_description=\"Renta Imp. 1ª  Cat. gastos rechazados. Art. 21 LIR.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"198\" value_description=\"Renta Imp. 1ª Cat. Subdeclaración retiros art. 14 bis LIR.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"199\" value_description=\"Renta Imp. G.C. No presentación declaración.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"200\" value_description=\"Renta Imp. G.C. No presentación dec. conjunta cónyuges.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"201\" value_description=\"Renta Imp. G.C. presentación declaración incompleta\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"202\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto 1ª Cat.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"203\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto Territorial\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"204\" value_description=\"Renta Imp. G.C. Declaración errónea Cotizaciones previsionales\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"205\" value_description=\"Renta Imp. G.C. Declaración errónea. Base imponible. Sumatoria\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"206\" value_description=\"Renta Imp. G.C. Declaración errónea. Imp. Único 2ª Cat\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"207\" value_description=\"Renta Imp. G.C. Dec. errónea. Crédito proporcional rentas exentas\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"208\" value_description=\"Renta Imp. G.C. Declaración errónea.Otro crédito\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"209\" value_description=\"Renta Imp. G.C. Dec. errónea. Cálculo incorrecto del impuesto\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"210\" value_description=\"Renta Imp. G.C. Declaración errónea. Art. 57 bis LIR \" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"257\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 4° DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"258\" value_description=\"Impuesto de timbres y estampillas. Artículo 2 DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"259\" value_description=\"Impuesto de timbres y estampillas. Artículo 3 DL N° 3475\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"260\" value_description=\"Impuesto a la herencia\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"261\" value_description=\"Impuesto a las donaciones\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"262\" value_description=\"Impuesto territorial. Sobretasa\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"263\" value_description=\"Impuesto territorial. Exención.\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"264\" value_description=\"Impuesto territorial. Otra\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"211\" value_description=\"Renta Imp. G.C. Declaración errónea. APV o Art. 42 bis LIR\" parent_field_id=\"20\" />\n";
    $xml .= "<valid_value value_id=\"265\" value_description=\"Renta Imp. 1ª  Cat. Subdeclaración u omisión de ingresos\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"266\" value_description=\"Renta Imp. 1ª  Cat. Reconocimiento costo que no corresponde\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"267\" value_description=\"Renta Imp. 1ª  Cat. Gastos rechazados. Primera categoría.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"268\" value_description=\"Renta Imp. 1ª  Cat. gastos rechazados. Art. 21 LIR.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"269\" value_description=\"Renta Imp. 1ª Cat. Subdeclaración retiros art. 14 bis LIR.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"270\" value_description=\"Renta Imp. G.C. No presentación declaración.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"271\" value_description=\"Renta Imp. G.C. No presentación dec. conjunta cónyuges.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"272\" value_description=\"Renta Imp. G.C. presentación declaración incompleta\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"273\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto 1ª Cat.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"274\" value_description=\"Renta Imp. G.C. Declaración errónea Impuesto Territorial\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"275\" value_description=\"Renta Imp. G.C. Declaración errónea Cotizaciones previsionales\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"276\" value_description=\"Renta Imp. G.C. Declaración errónea. Base imponible. Sumatoria\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"277\" value_description=\"Renta Imp. G.C. Declaración errónea. Imp. Único 2ª Cat\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"278\" value_description=\"Renta Imp. G.C. Dec. errónea. Crédito proporcional rentas exentas\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"279\" value_description=\"Renta Imp. G.C. Declaración errónea.Otro crédito\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"280\" value_description=\"Renta Imp. G.C. Dec. errónea. Cálculo incorrecto del impuesto\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"281\" value_description=\"Renta Imp. G.C. Declaración errónea. Art. 57 bis LIR \" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"282\" value_description=\"Renta Imp. G.C. Declaración errónea. APV o Art. 42 bis LIR\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"283\" value_description=\"Renta Imp. G.C. Dec. errónea. Retenciones Art. 42 N° 2 LIR\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"284\" value_description=\"Renta Imp. G.C. Dec. errónea. Créditos socios o comuneros\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"285\" value_description=\"Renta Imp. G.C. Dec. errónea. Reliquidación por Término giro\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"286\" value_description=\"Renta Impuesto Adicional. Marcas, patentes y otros\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"287\" value_description=\"Renta Imp. Adicional. Patentes de invención, de modelos de utilidad\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"288\" value_description=\"Renta Imp. Adicional. Programas computacionales\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"289\" value_description=\"Renta Imp. Adicional. Regalías o asesorias improductivas\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"290\" value_description=\"Renta Imp. Adicional. Materiales de cine o televisón\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"291\" value_description=\"Renta Imp. Adicional. Derecho de edición o de autor\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"292\" value_description=\"Renta Imp. Adicional. Intereses\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"293\" value_description=\"Renta Imp. Adicional. Depósitos\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"294\" value_description=\"Renta Imp. Adicional. Créditos\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"295\" value_description=\"Renta Imp. Adicional. Saldos de precio\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"296\" value_description=\"Renta Imp. Adicional. Bonos o debentures\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"297\" value_description=\"Renta Imp. Adicional. Aceptaciones bancarias latinoamer.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"298\" value_description=\"Renta Imp. Adicional. Instrumentos deuda pública. Art.104 LIR.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"299\" value_description=\"Renta Imp. Adicional. Remuneraciones servicios en el extranjero\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"300\" value_description=\"Renta Imp. Adicional. Primas de Serguro\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"301\" value_description=\"Renta Imp. Adicional. Fletes marítimos\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"302\" value_description=\"Renta Imp. Adicional. Uso o goce temporal naves extranjeras\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"303\" value_description=\"Renta Imp. Adicional. Art.59 N° 6 LIR\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"304\" value_description=\"Renta Imp. Adicional. Art. 60 LIR\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"305\" value_description=\"Renta Imp. Adicional. Chilenos no residentes ni domiciliados en Chile\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"306\" value_description=\"Renta Impuesto único a los premios de loteria\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"307\" value_description=\"Renta Impuesto único de Primera Categoría\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"308\" value_description=\"Renta Impuesto único de Sergunda Categoría\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"309\" value_description=\"Iva-Ventas. Hecho gravado general\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"310\" value_description=\"Iva-Ventas. Artículo 8) Letra a)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"311\" value_description=\"Iva-Ventas. Artículo 8) Letra b)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"312\" value_description=\"Iva-Ventas. Artículo 8) Letra c)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"313\" value_description=\"Iva-Ventas. Artículo 8) Letra d)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"314\" value_description=\"Iva-Ventas. Artículo 8) Letra e)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"315\" value_description=\"Iva-Ventas. Artículo 8) Letra f)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"316\" value_description=\"Iva-Ventas. Artículo 8) Letra k)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"317\" value_description=\"Iva-Ventas. Artículo 8) Letra l)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"318\" value_description=\"Iva-Ventas. Artículo 8) Letra m)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"319\" value_description=\"Iva-Servicios. Hecho gravado general\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"320\" value_description=\"Iva-Servicios. Artículo 8 Letra e)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"321\" value_description=\"Iva-Servicios. Artículo 8 Letra g)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"322\" value_description=\"Iva-Servicios. Artículo 8 Letra h)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"323\" value_description=\"Iva-Servicios. Artículo 8 Letra i)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"324\" value_description=\"Iva-Servicios. Artículo 8 Letra j)\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"325\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°1 DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"326\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 1° DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"327\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 3° DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"328\" value_description=\"Impuesto de timbres y estampillas. Artículo 1 N°3 inc. 4° DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"329\" value_description=\"Impuesto de timbres y estampillas. Artículo 2 DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"330\" value_description=\"Impuesto de timbres y estampillas. Artículo 3 DL N° 3475\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"331\" value_description=\"Impuesto a la herencia\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"332\" value_description=\"Impuesto a las donaciones\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"333\" value_description=\"Impuesto territorial. Sobretasa\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"334\" value_description=\"Impuesto territorial. Exención.\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"335\" value_description=\"Impuesto territorial. Otra\" parent_field_id=\"21\" />\n";
    $xml .= "<valid_value value_id=\"336\" value_description=\"Art. 126 N° 1 CT\" parent_field_id=\"22\" />\n";
    $xml .= "<valid_value value_id=\"337\" value_description=\"Art. 126 N° 2 CT\" parent_field_id=\"22\" />\n";
    $xml .= "<valid_value value_id=\"338\" value_description=\"Art. 126 N° 3 CT\" parent_field_id=\"22\" />\n";
    $xml .= "<valid_value value_id=\"339\" value_description=\"Art. 126 inciso final CT\" parent_field_id=\"22\" />\n";
    $xml .= "<valid_value value_id=\"343\" value_description=\"Art. 149 N° 1 CT\" parent_field_id=\"26\" />\n";
    $xml .= "<valid_value value_id=\"344\" value_description=\"Art. 149 N° 2 CT\" parent_field_id=\"26\" />\n";
    $xml .= "<valid_value value_id=\"345\" value_description=\"Art. 149 N° 3 CT\" parent_field_id=\"26\" />\n";
    $xml .= "<valid_value value_id=\"346\" value_description=\"Art. 149 N° 4 CT\" parent_field_id=\"26\" />\n";
    $xml .= "<valid_value value_id=\"350\" value_description=\"Art. 149 N° 4 CT\" parent_field_id=\"27\" />\n";
    $xml .= "<valid_value value_id=\"347\" value_description=\"Art. 149 N° 1 CT\" parent_field_id=\"27\" />\n";
    $xml .= "<valid_value value_id=\"348\" value_description=\"Art. 149 N° 2 CT\" parent_field_id=\"27\" />\n";
    $xml .= "<valid_value value_id=\"349\" value_description=\"Art. 149 N° 3 CT\" parent_field_id=\"27\" />\n";
    $xml .= "<valid_value value_id=\"354\" value_description=\"Art. 10 letra d) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"355\" value_description=\"Art. 10 letra e) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"356\" value_description=\"Art. 10 letra f) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"357\" value_description=\"Art. 10 letra g) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"358\" value_description=\"Art. 11 letra a) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"359\" value_description=\"Art. 11 letra b) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"351\" value_description=\"Art. 10 letra a) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"352\" value_description=\"Art. 10 letra b) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"353\" value_description=\"Art. 10 letra c) Ley 17.235\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"360\" value_description=\"Art. 25 Ley 15.163\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"361\" value_description=\"Art. 26 Ley 15.163\" parent_field_id=\"28\" />\n";
    $xml .= "<valid_value value_id=\"362\" value_description=\"Art. 10 letra a) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"363\" value_description=\"Art. 10 letra b) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"364\" value_description=\"Art. 10 letra c) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"365\" value_description=\"Art. 10 letra d) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"366\" value_description=\"Art. 10 letra e) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"367\" value_description=\"Art. 10 letra f) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"368\" value_description=\"Art. 10 letra g) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"369\" value_description=\"Art. 12 letra a) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"370\" value_description=\"Art. 12 letra b) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"371\" value_description=\"Art. 12 letra c) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"372\" value_description=\"Art. 12 letra d) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"373\" value_description=\"Art. 12 letra e) Ley 17.235\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"374\" value_description=\"Art. 25 Ley 15.163\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"375\" value_description=\"Art. 26 Ley 15.163\" parent_field_id=\"29\" />\n";
    $xml .= "<valid_value value_id=\"13\" value_description=\"Relacionadas con ingreso de mercancías\" parent_field_id=\"6\" />\n";
    $xml .= "<valid_value value_id=\"14\" value_description=\"Relacionadas con salida de mercancías\" parent_field_id=\"6\" />\n";
    $xml .= "<valid_value value_id=\"15\" value_description=\"Otros actos u omisiones\" parent_field_id=\"6\" />\n";
    $xml .= "<valid_value value_id=\"16\" value_description=\"Relacionadas con ingreso de mercancías\" parent_field_id=\"7\" />\n";
    $xml .= "<valid_value value_id=\"17\" value_description=\"Relacionadas con salida de mercancías\" parent_field_id=\"7\" />\n";
    $xml .= "<valid_value value_id=\"18\" value_description=\"Otros actos u omisiones\" parent_field_id=\"7\" />\n";
    $xml .= "<valid_value value_id=\"19\" value_description=\"Relacionadas con ingreso de mercancías\" parent_field_id=\"8\" />\n";
    $xml .= "<valid_value value_id=\"20\" value_description=\"Relacionadas con salida de mercancías\" parent_field_id=\"8\" />\n";
    $xml .= "<valid_value value_id=\"21\" value_description=\"Otros actos u omisiones\" parent_field_id=\"8\" />\n";
    $xml .= "<valid_value value_id=\"4\" value_description=\"Otros cargos\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"1\" value_description=\"Clasificación\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"2\" value_description=\"Origen\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"3\" value_description=\"Valoración\" parent_field_id=\"1\" />\n";
    $xml .= "<valid_value value_id=\"7\" value_description=\"Relacionadas con origen\" parent_field_id=\"2\" />\n";
    $xml .= "<valid_value value_id=\"8\" value_description=\"Otras actuaciones\" parent_field_id=\"2\" />\n";
    $xml .= "<valid_value value_id=\"6\" value_description=\"Relacionadas con clasificación\" parent_field_id=\"2\" />\n";
    $xml .= "<valid_value value_id=\"5\" value_description=\"Relacionadas con valoración\" parent_field_id=\"2\" />\n";
    $xml .= "<valid_value value_id=\"9\" value_description=\"Valoración\" parent_field_id=\"3\" />\n";
    $xml .= "<valid_value value_id=\"10\" value_description=\"Clasificación\" parent_field_id=\"3\" />\n";
    $xml .= "<valid_value value_id=\"22\" value_description=\"Manifiesto general\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"23\" value_description=\"Lista de pasajeros\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"24\" value_description=\"Guía de correos\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"25\" value_description=\"Lista de efectos personales tripulación\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"26\" value_description=\"Lista de contenedores vacíos\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"27\" value_description=\"Otros documentos\" parent_field_id=\"9\" />\n";
    $xml .= "<valid_value value_id=\"28\" value_description=\"Clasificación\" parent_field_id=\"10\" />\n";
    $xml .= "<valid_value value_id=\"30\" value_description=\"Valoración\" parent_field_id=\"10\" />\n";
    $xml .= "<valid_value value_id=\"28\" value_description=\"Clasificación\" parent_field_id=\"11\" />\n";
    $xml .= "<valid_value value_id=\"30\" value_description=\"Valoración\" parent_field_id=\"11\" />\n";
    $xml .= "<valid_value value_id=\"32\" value_description=\"Artículo 176 letra a) \" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"33\" value_description=\"Artículo 176 letra b) \" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"34\" value_description=\"Artículo 176 letra c)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"35\" value_description=\"Artículo 176 letra d)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"36\" value_description=\"Artículo 176 letra e)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"37\" value_description=\"Artículo 176 letra f)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"38\" value_description=\"Artículo 176 letra g)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"39\" value_description=\"Artículo 176 letra h)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"40\" value_description=\"Artículo 176 letra i)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"41\" value_description=\"Artículo 176 letra j)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"42\" value_description=\"Artículo 176 letra k)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"43\" value_description=\"Artículo 176 letra l)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"44\" value_description=\"Artículo 176 letra m)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"45\" value_description=\"Artículo 176 letra n)\" parent_field_id=\"12\" />\n";
    $xml .= "<valid_value value_id=\"46\" value_description=\"Artículo 176 letra ñ)\" parent_field_id=\"12\" />\n";
    $xml .= "</field>\n";
    $xml .= "<field name=\"content_url\" type=\"string\" />\n";
    $xml .= "<field name=\"ruc\" type=\"string\" />\n";
    $xml .= "<field name=\"rit\" type=\"string\"/>\n";
    $xml .= "<field name=\"title\" type=\"string\" />\n";
    $xml .= "<field name=\"abstract\" type=\"string\" />\n";
    $xml .= "<field name=\"document_type\" type=\"list\" >\n";

    foreach my $llave (keys %hash_document_type){
         $xml .= "<valid_value value_id=\"".$hash_document_type{$llave}."\" value_description=\"".$llave."\" />\n";
    } 

    $xml .= "</field>\n";
    $xml .= "<field name=\"section\" type=\"list\" >\n";
    $xml .= "<valid_value value_id=\"01\" value_description=\"Acuerdo\" />\n";
    $xml .= "<valid_value value_id=\"02\" value_description=\"Resolucion de Sala\" />\n";
    $xml .= "<valid_value value_id=\"03\" value_description=\"Resolucion de Presidencia\" />\n";
    $xml .= "<valid_value value_id=\"04\" value_description=\"Circular\" />\n";
    $xml .= "<\/field>\n";
    $xml .= "<\/fields>\n";
    $xml .= "<\/config>\n";
    return $xml;
}
	
sub settextofile{
    my ($texto,$DOCUMENT_ID)=@_;
    my $directorio=$1 if ($DOCUMENT_ID=~/(.*?)\/[^\/]+$/is);
    $directorio=~s/^[<>]//is;
    crear_directorio($directorio);
    open (ARCHIVO,"$DOCUMENT_ID");
    print ARCHIVO $texto;
    close(ARCHIVO);
}

sub crear_directorio{
    my ($destino)=@_;
    my @directorios=split (/\//,$destino);
    my $dir_temp="/";
    while (defined (my $dir = shift @directorios)){
        $dir_temp.="/".$dir;
        if (! -e $dir_temp){
            mkdir($dir_temp);
            }
        }
}

sub log_msj{

    my ($msj, $path) = @_;
    my @callerinfo = caller 0;

    if((!$path || !-d $path) && $callerinfo[1] =~ /^(.+)\//){
        $path = $1 if(-d $1);
    }
    else{
        $path = $ENV{'PWD'} unless($path && -d $path);
    }

    if(!-d "$path/logs"){
        mkdir("$path/logs");
    }
    croak "Imposible crear directorio LOGS en $path" if(!-d "$path/logs");

    ## Chequeo el tamaño del archivo que no sea mayor a 5 MB, si es mayor, lo borro.
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat("$path/logs/info.log");
    $size = $size / 1024 if($size && $size > 0);
    if($size && $size > 0){
        $size = $size / 1024;
        unlink("$path/logs/info.log") if($size > 5);
    }

    #################

    open FILE, ">>", "$path/logs/info.log";
    print FILE "$msj\n";
    close FILE;
    if (-t STDIN && -t STDOUT) {
        print "$msj\n";
    }

}
sub extraer_texto{
    my %params = @_;
    my $response = $browser->get($params{url});
    return $response->content;
}

sub limpiar_texto{
    my %params = @_;

    $params{marginal} =~s/^\d+\///isg; 
    $params{texto} = $1 if $params{texto} =~ /$params{marginal}<\/strong>(.*?<\/body>)/is;
    my $reg_exp = $params{titulo};
    $reg_exp =~ s/([^a-z0-9 ])/.{1,2}/isg;
    $params{texto} =~s/^(?:<[^>]+>)*<strong>$reg_exp[^<]*<\/strong>//is;

    $params{texto} = process_tables(texto => $params{texto}, clean_useless_tags => 'no');
    $params{texto}=~s/<td.*?>/##td##/isg;
    $params{texto}=~s/<th.*?>/##th##/isg;
    $params{texto}=~s/<tr.*?>/##tr##/isg;
    $params{texto}=~s/<table.*?>/##table##/isg;
    $params{texto}=~s/<\/td>/##\/td##/isg;
    $params{texto}=~s/<\/th>/##\/th##/isg;
    $params{texto}=~s/<\/tr>/##\/tr##/isg;
    $params{texto}=~s/<\/table>/##\/table##/isg;

    $params{texto}=~s/\r?\n/ /isg;
    $params{texto}=~s/\t/ /isg;
    $params{texto}=~s/ {2,}/ /isg;
    $params{texto}=~s/<\/p>/\n\n/isg;
    $params{texto}=~s/<[^>]+>//isg;
    $params{texto}=~s/^[ \n]+//mg;

    $params{texto}=~s/##td##/<td>/isg;
    $params{texto}=~s/##th##/<th>/isg;
    $params{texto}=~s/##tr##/<tr>/isg;
    $params{texto}=~s/##table##/<table>/isg;
    $params{texto}=~s/##\/td##/<\/td>/isg;
    $params{texto}=~s/##\/th##/<\/th>/isg;
    $params{texto}=~s/##\/tr##/<\/tr>/isg;
    $params{texto}=~s/##\/table##/<\/table>/isg;
    
    return $params{texto};
}



sub recuperar_emisor{
    my %params = @_;
    $params{marginal} =~s/^\d+\///isg; 
    $params{texto} = $1 if $params{texto} =~ /(<p class="txtprincipal">.*)<strong>$params{marginal}/is;
    my %retorno;
    while ($params{texto} =~ /<p class="txtprincipal">(.*?)<\/p>/isg){
        my $tmp = $1;
        $retorno{emisor} = $1 if $tmp =~ /<strong>(.*?)<\/strong>/is;
        $retorno{subemisor} = $1 if $tmp =~ /<p class="txtprincipal">(.*?)<\/p>/is && $tmp !~/<strong>/;
    }
    return %retorno;
}
