/**************************************************************************
   Desenvolvido por: Felipe Silva e Rodrigo Donha
   Data de Criação: 07/10/2013
   Funcionalidade: Utilizado para enviar exception com objetivo de evitar erros 
**************************************************************************/
public class DAOException extends Exception
{
	private String mensagemTratada{get; set;}
	
	private String linhaDoErro{get; set;}
	private String stackTrace{get; set;}
	private String classeRaizExcecao{get; set;}	
	public String nomeClasse{get; set;}
	public String nomeMetodo{get; set;}


	/* Gera exceção a partir dos parêmtros informados **/
	public DAOException( String message, String nomeClasse, String nomeMetodo, Exception e )
	{
		this( message );
		
		initCause( e );
		
		this.linhaDoErro = String.valueOf( getLineNumber() );
		this.stackTrace = getStackTraceString();
		this.classeRaizExcecao = getTypeName();

		this.nomeClasse = nomeClasse;
		this.nomeMetodo = nomeMetodo;

		criarMensagemTratada();
	}


	/* Gera exceção a partir dos parêmtros informados **/
	public DAOException( String message, String nomeClasse, String nomeMetodo )
	{
		this( message );
		
		this.linhaDoErro = String.valueOf( getLineNumber() );
		this.stackTrace = getStackTraceString();
		this.classeRaizExcecao = getTypeName();

		this.nomeClasse = nomeClasse;
		this.nomeMetodo = nomeMetodo;

		criarMensagemTratada();
	}
	
	
	/* Retorna mensagem tratada**/
	public String obterMensagemTratada()
	{
		//this.mensagemTratada = criarMensagemTratada();
		return this.mensagemTratada;
	}


	/* Trata a mensagem da exceção **/
	private void criarMensagemTratada()
	{
		this.mensagemTratada = getMessage() + '. \r\n';
		this.mensagemTratada += 'Linha do erro: ' + this.linhaDoErro + '; \r\n\r\n';
		this.mensagemTratada += 'Stacktrace: ' + this.stackTrace + '; \r\n\r\n';
		this.mensagemTratada += 'Exceção: ' + this.classeRaizExcecao + '; \r\n\r\n';
		this.mensagemTratada += 'Nome da classe: ' + this.nomeClasse + '; \r\n\r\n';
		this.mensagemTratada += 'Nome do método: ' + this.nomeMetodo + '; \r\n\r\n';
	}
	
	

}