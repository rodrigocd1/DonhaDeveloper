/**************************************************************************
   Desenvolvido por: Leonardo Fernandes de Assunção;
   Data de Criação: 08/10/2013;
   Funcionalidade: Componente de Expressão regular : Validações de tipos de dados em String.
**************************************************************************/
public class OzExpressaoRegular {

	/** Utilizado para verificar se no atributo informado por parâmetro contém caracteres de A a Z. */
	public static Boolean atributoInformadoSoContemLetrasDeAaZ( String atributo )
	{
		return Pattern.matches('[a-zA-Z]+', atributo );
	}
	
	
	
	/** Utilizado para verificar se no atributo informado por parâmetro contém apenas números. */
	public static Boolean atributoInformadoSoContemNumeros( String atributo )
	{
		return Pattern.matches('[0-9]+', atributo );
	}


	
	/** Utilizado para verificar se no atributo informado por parâmetro contém caracteres de A a Z e Alphanumericos. */
	public static Boolean atributoInformadoSoContemLetrasDeAaZEAlphanumericos( String atributo )
	{
		return Pattern.matches('^[\\w\\s&&[^\\d]]+$', atributo );
	}



	/** Utilizado para verificar se o email informado está no formato correto. */
	public static Boolean emailInformadoEstaNoFormatoCorreto( String email )
	{
		String pat = '^[_A-Za-z0-9-\\+]+(\\.[_A-Za-z0-9-]+)*@[A-Za-z0-9-]+(\\.[A-Za-z0-9]+)*(\\.[A-Za-z]{2,})$';
		return Pattern.matches( pat, email ); 
	}



	/** Utilizado para verificar se a data informada está no formato MM/AAAA */
	public static Boolean dataInformadaEstaNoFormatoMMAAAA( String dataInformada )
	{
		return Pattern.matches('^([0-9]{2}/[0-9]{4})$', dataInformada );
	}

}