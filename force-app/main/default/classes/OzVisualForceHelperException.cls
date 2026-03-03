/**********************************************************************************************************************************************************************

  @description Classe utilizada para enviar exceções relacionadas às classes OzVisualForceHelper.
  @author Avanxo - Vitor Finati - Rodrigo Donha
  @date 26/03/2014
  @see OzVisualForceHelper

**********************************************************************************************************************************************************************/

public class OzVisualForceHelperException extends Exception
{
	
	private String mensagemTratada{get; set;}
  	private String linhaDoErro{get; set;}
  	private String stackTrace{get; set;}
  	private String classeRaizExcecao{get; set;}   
  	public String nomeClasse{get; set;}
  	public String nomeMetodo{get; set;}
 
 
 	
 	/** 
		@description Construtor da classe OzVisualForceHelperException
		@param message String que armazena a mensagem de erro.
		@param nomeClasse String que armazena o nome da classe em que ocorreu o erro.
		@param nomeMetodo String que possui o nome do metodo em que ocorreu o erro.
		@param e Exception do que foi gerada no erro
		@author Avanxo - Vitor Finati - Rodrigo Donha
 		@date 26/03/2014
 	*/
  	public OzVisualForceHelperException( String message, String nomeClasse, String nomeMetodo, Exception e )
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
 
 
 	
 	/** 
		@description Construtor da classe OzVisualForceHelperException
		@param message String que armazena a mensagem de erro.
		@param nomeClasse String que armazena o nome da classe em que ocorreu o erro.
		@param nomeMetodo String que possui o nome do metodo em que ocorreu o erro.
		@author Avanxo - Vitor Finati - Rodrigo Donha
 		@date 26/03/2014
 	*/
  	public OzVisualForceHelperException( String message, String nomeClasse, String nomeMetodo )
  	{
    	this( message );
           
        this.linhaDoErro = String.valueOf( getLineNumber() );
        this.stackTrace = getStackTraceString();
        this.classeRaizExcecao = getTypeName();
        this.nomeClasse = nomeClasse;
        this.nomeMetodo = nomeMetodo;
 
        criarMensagemTratada();
  	}
     
     
    
    /** 
		@description Método privado que gera a mensagem de erro que sera apresentada na tela
		@author Avanxo - Vitor Finati - Rodrigo Donha
		@return void
 		@date 26/03/2014
 	*/ 
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