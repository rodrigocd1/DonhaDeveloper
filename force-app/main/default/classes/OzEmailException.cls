public virtual class OzEmailException extends Exception{


	private String mensagemTratada{get; set;}
	private String linhaDoErro{get; set;}
	private String stackTrace{get; set;}
	private String classeRaizExcecao{get; set;}	
	private String nomeClasse{get; set;}
	private String nomeMetodo{get; set;}



	public OzEmailException( String message, String nomeClasse, String nomeMetodo, Exception e )
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

	
	
	public OzEmailException( String message, String nomeClasse, String nomeMetodo )
	{
		this( message );
		
		this.linhaDoErro = String.valueOf( getLineNumber() );
		this.stackTrace = getStackTraceString();
		this.classeRaizExcecao = getTypeName();

		this.nomeClasse = nomeClasse;
		this.nomeMetodo = nomeMetodo;

		criarMensagemTratada();
	}
	
	
	
	public String obterMensagemTratada()
	{
		//this.mensagemTratada = criarMensagemTratada();
		return this.mensagemTratada;
	}



	private void criarMensagemTratada()
	{
		this.mensagemTratada = getMessage() + '. \r\n';
		this.mensagemTratada += 'Linha do erro: ' + this.linhaDoErro + ' \r\n';
		this.mensagemTratada += 'Stacktrace: ' + this.stackTrace + ' \r\n';
		this.mensagemTratada += 'Exceção: ' + this.classeRaizExcecao + ' \r\n';
		this.mensagemTratada += 'Nome da classe: ' + this.nomeClasse + ' \r\n';
		this.mensagemTratada += 'Nome do método: ' + this.nomeMetodo + ' \r\n';
	}
}