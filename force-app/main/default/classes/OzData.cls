/**************************************************************************
   Desenvolvido por: Leonardo Fernandes de Assunção;
   Data de Criação: 08/10/2013;
   Funcionalidade: Componente de Data : Transformações de tipos de dados em um formato Data e vice versa.
   				   
**************************************************************************/
public class OzData 
{
	
	
	
	/** Esse método tem como função reotornar uma Data vindo de um campo String.
		obterDatePorStringFormatoDDMMYYYY */
	public static Date obterDatePorStringFormatoDDMMYYYY( String dataEmString ) {
		
		if ( ( dataEmString == '' ) || ( dataEmString == null ) )
		{
			throw new OzDataException( 'Não foi possível obterDatePorStringFormatoDDMMYYYY. O parâmetro dataEmString não foi informado', 
								       'OzData',
								       'obterDatePorStringFormatoDDMMYYYY' );
		}
		
		try{
					
			Date dataUtil = null;
			String mes= dataEmString.subString(0,2);
			String dia= dataEmString.subString(3,5);
			String ano= dataEmString.subString(6,10);
			return dataUtil = Date.newInstance(integer.valueOf(ano), integer.valueOf(dia), integer.valueOf(mes));
		}
		catch( Exception e )
		{
			throw new OzDataException( e.getMessage(), 'OzData', 'obterDatePorStringFormatoDDMMYYYY', e );
		}
		return null;
	}
	
	
	
	/** Esse método tem como função retornar uma String formata de Uma data, do tipo 
		Datetime, com a finalidade de facilitar a comparação de Datas em Query's dinâmicas. */
	public static String obterStringDataFormatoSalesPorDateTime(Datetime dataParaformatar) 
	{
		if(dataParaformatar == null)
		{
			throw new OzDataException( 'Não foi possível obterStringDataFormatoSalesPorDateTime. O parâmetro dataParaformatar não foi informado', 
								       'OzData',
								       'obterStringDataFormatoSalesPorDateTime' );		
		}
		

			String dataFormatada = String.valueOf(dataParaformatar);
			dataFormatada = dataFormatada.replace(' ','T');
			dataFormatada += '.000Z';
			return dataFormatada;

		
	}


	
	/** Retorna Data com mais 365 dias. */
	public static Date criarDataAtualMais365Dias()
	{
		Date dataMais365Dias = Date.today();
		dataMais365Dias = dataMais365Dias.addYears( 1 );
		return dataMais365Dias;
	}
	
	
	
	/** Utilizado para retornar uma data do tipo string no seguinte formato:
    YYYY-MM-DD
    Pelo objeto Date informado por parâmetro. */	
	public static String obterStringDataNoFormatoYYYYMMDD( Date dataFormatoYYYYMMDD )
	{
		if(dataFormatoYYYYMMDD == null)
		{
			throw new OzDataException( 'Não foi possível obterStringDataNoFormatoYYYYMMDD. O parâmetro dataFormatoYYYYMMDD não foi informado', 
								       'OzData',
								       'obterStringDataNoFormatoYYYYMMDD' );
		}
		
		Integer mes = dataFormatoYYYYMMDD.month();
		
		String descMes = null;
		if ( mes < 10 )
			descMes = '0' + mes; 
		else
		{
			descMes = String.valueOf( mes );
		}
		
		Integer dia = dataFormatoYYYYMMDD.day();
		String descDia = null;
		
		if ( dia < 10 )
			descDia = '0' + dia; 
		else
		{
			descDia = String.valueOf( dia );
		}
		
		return dataFormatoYYYYMMDD.year() + '-' + descMes + '-' + descDia;
	}	
	
	
	
	/** Esse método tem como função retornar uma String no formato de data com hiféns. */
	public static String adicionarHifenNaData( String dataFormatoYYYYMMDD )
	{
		if ( dataFormatoYYYYMMDD != null && dataFormatoYYYYMMDD.trim() != '' )
		{
			String dataFormatada = dataFormatoYYYYMMDD.substring( 0,4 )  + '-' + 
								   dataFormatoYYYYMMDD.substring( 4,6 ) + '-' + 
								   dataFormatoYYYYMMDD.substring( 6,8 );
		 	return dataFormatada;	
		}
		else
		{
			throw new OzDataException( 'Não foi possível adicionarHifenNaData. O parâmetro dataFormatoYYYYMMDD não foi informado', 
								       'OzData',
								       'adicionarHifenNaData' );					
			return null;
		}
	}
	
	
	
	/** Método utilizado para retornar a diferença em segundos (Inteiro) entre duas datas no formato (DateTime). */	
	public static Integer obterDiferencaEmSegundos( Datetime primeiraData, Datetime segundaData )
	{  
		if(primeiraData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmSegundos. O parâmetro primeiraData não foi informado', 
								       'OzData',
								       'obterDiferencaEmSegundos' );			
		}
		
		if(segundaData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmSegundos. O parâmetro segundaData não foi informado', 
								       'OzData',
								       'obterDiferencaEmSegundos' );			
		}		
   		long dt1 = primeiraData.getTime() / 1000;  
   		long dt2 = segundaData.getTime() / 1000;
   		double diferenca = dt1 - dt2;
   	
		Integer segundosInteiro = Integer.valueOf( diferenca );

   		return segundosInteiro;
	}
	
	
	
	/** Método utilizado para retornar a diferença em segundos (Decimal) entre duas datas no formato (DateTime). */
	public static Decimal obterDiferencaEmSegundosDecimal( Datetime primeiraData, Datetime segundaData )
	{  
		if(primeiraData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmSegundosDecimal. O parâmetro primeiraData não foi informado', 
								       'OzData',
								       'obterDiferencaEmSegundosDecimal' );			
		}
		
		if(segundaData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmSegundosDecimal. O parâmetro segundaData não foi informado', 
								       'OzData',
								       'obterDiferencaEmSegundosDecimal' );			
		}	
		
   		Decimal data1 = primeiraData.getTime() / 1000;  
   		Decimal data2 = segundaData.getTime() / 1000;

   		return data1 - data2; 
	}
	
	
	
	
	/** Obter a difenrênça em milisegundos entre duas datas no formato (DateTime). */
	public static Long obterDiferencaEmMilisegundos( Datetime primeiraData, Datetime segundaData )
	{ 
		
		if(primeiraData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMilisegundos. O parâmetro primeiraData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMilisegundos' );			
		}
		
		if(segundaData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMilisegundos. O parâmetro segundaData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMilisegundos' );			
		}		
		 
		BusinessHours horario = [select id from businesshours where IsDefault=true];
		Long diferenca = BusinessHours.diff( horario.id, primeiraData, segundaData );

   		return diferenca;
	}
	
	
	
	/** Obter a difenrênça em milisegundos entre duas datas no formato (DateTime). */
	public static Decimal obterDiferencaEmMilisegundosDecimal( Datetime primeiraData, Datetime segundaData )
	{  
		if(primeiraData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMilisegundosDecimal. O parâmetro primeiraData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMilisegundosDecimal' );			
		}
		
		if(segundaData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMilisegundosDecimal. O parâmetro segundaData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMilisegundosDecimal' );			
		}
		
		BusinessHours horario = [select id from businesshours where IsDefault=true];
		Decimal diferenca = BusinessHours.diff( horario.id, primeiraData, segundaData );
		diferenca = diferenca / 1000;
		
   		return diferenca;
	}
	 
	
	
	/** Método utilizado para retornar a diferença em minutos entre duas datas no formato (DateTime). */
	public static Integer obterDiferencaEmMinutos( Datetime primeiraData, Datetime segundaData )
	{  
		if(primeiraData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMinutos. O parâmetro primeiraData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMinutos' );			
		}
		
		if(segundaData == null)
		{
			throw new OzDataException( 'Não foi possível obterDiferencaEmMinutos. O parâmetro segundaData não foi informado', 
								       'OzData',
								       'obterDiferencaEmMinutos' );			
		}
		
   		long data1 = primeiraData.getTime() / 1000 / 60;  
   		long data2 = segundaData.getTime() / 1000 / 60;
   		double diferenca = data1 - data2;
   		
   		Integer minutosInt = Integer.valueOf( diferenca );
   		
   		return minutosInt;
	}
	
	
	
	/** Método utilizado para obter o tempo de processamento de dois datetimes informados.
	    Formato retornado Minutos, Segundos e Milisegundos: MM:SS:MMMM. */
    public static String obterTempoDeProcessamentoPorDataInformadas( DateTime dateFim, DateTime dateInicio )
    {
		if(dateFim == null)
		{
			throw new OzDataException( 'Não foi possível obterTempoDeProcessamentoPorDataInformadas. O parâmetro dateFim não foi informado', 
								       'OzData',
								       'obterTempoDeProcessamentoPorDataInformadas' );			
		}
		
		if(dateInicio == null)
		{
			throw new OzDataException( 'Não foi possível obterTempoDeProcessamentoPorDataInformadas. O parâmetro dateInicio não foi informado', 
								       'OzData',
								       'obterTempoDeProcessamentoPorDataInformadas' );			
		}    	
    	
        Decimal minutos = obterDiferencaEmMinutos( dateFim, dateInicio );
        Decimal segundos = obterDiferencaEmSegundosDecimal( dateFim, dateInicio );
        Long milisegundos = obterDiferencaEmMilisegundos( dateInicio, dateFim );

        String strSeg = null;
        if ( segundos < 10 )
        {
            strSeg = '0' + String.valueOf( segundos );
        }
        else
        {
            strSeg = String.valueOf( segundos );
        }

        String retorno = '0' + String.valueOf( minutos ) + ':' + strSeg + ':' + obterMilisegundosFormatado( milisegundos );

        return retorno;
    }
    
    
    
    /** Método utilizado para recuperar os milisegundos de um objeto Long. */
    public static String obterMilisegundosFormatado( Long milisegundos )
	{
		if(milisegundos == null)
		{
			throw new OzDataException( 'Não foi possível obterMilisegundosFormatado. O parâmetro milisegundos não foi informado', 
								       'OzData',
								       'obterMilisegundosFormatado' );
		}							       		
		
		String strMilisegundos = null;
		if ( milisegundos == null || milisegundos == 0 )
		{
			strMilisegundos = '0000';
		}
		else 
		{
			strMilisegundos = String.valueOf( milisegundos );
			if ( strMilisegundos.length() == 1 )
			{
				strMilisegundos = '000' + milisegundos;
			}
			else if ( strMilisegundos.length() == 2 )
			{
				strMilisegundos = '00' + milisegundos;
			}
			else if ( strMilisegundos.length() == 3 )
			{
				strMilisegundos = '0' + milisegundos;
			}
		}

		return strMilisegundos;
	}
	
	/* Recebe a data hora no formato YYYY - MM - DD HH:MM:SS
	   Retorna String no formato  DD - MM - YYYY HH:MM:SS **/
	public static String obterStringDataHoraFormatoDDMMYYYYHHMMSS(Datetime dataHora)
	{	
		if(dataHora == null)  
		{	 	
			throw new OzDataException( 'Não foi possível obterDatePorStringFormatoDDMMYYYYHHMMSS. O parâmetro dataHora não foi informado', 
								       'OzData',
								       'obterStringDataHoraFormatoDDMMYYYY_HHMMSS' );    		
		}
		
		String dataformatada = (dataHora.format('dd/MM/YYYY HH:mm:ss'));
    	return dataformatada;
		
	}
	
}