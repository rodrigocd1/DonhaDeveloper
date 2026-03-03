public class OzVisualForceMensagens 
{
	/*Exibir mensagem com um símbulo de Informação.**/
	public static void exibirMensagemInformacao( String mensagem )
	{
		if(mensagem != null)
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.INFO, mensagem );
        	ApexPages.addMessage( msg );
		}
		else
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, ' O texto da função de mensagem não foi informado! ' );
        	ApexPages.addMessage( msg );
		}	
	}
	
	/*Exibir mensagem com um símbulo de Erro.**/
	public static void exibirMensagemErro( String mensagem )
	{
		if(mensagem != null)
		{		
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.ERROR, mensagem );
	        ApexPages.addMessage( msg );
        }
		else
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, ' O texto da função de mensagem não foi informado! ' );
        	ApexPages.addMessage( msg );
		}	
	}
	
	/*Exibir mensagem com um símbulo de Erro.**/
	public static void exibirMensagemErroFatal( String mensagem )
	{
		if(mensagem != null)
		{		
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, mensagem );
	        ApexPages.addMessage( msg );
		}
		else
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, ' O texto da função de mensagem não foi informado! ' );
        	ApexPages.addMessage( msg );
		}	
	}
	
	/*Exibir mensagem com um símbulo de Sucesso.**/
	public static void exibirMensagemSucesso( String mensagem )
	{
		if(mensagem != null)
		{		
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.CONFIRM, mensagem );
	        ApexPages.addMessage( msg );
		}
		else
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, ' O texto da função de mensagem não foi informado! ' );
        	ApexPages.addMessage( msg );
		}	
	}
	
	/*Exibir mensagem com um símbulo de Aviso.**/
	public static void exibirMensagemAviso( String mensagem )
	{
		if(mensagem != null)
		{		
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.WARNING, mensagem );
	        ApexPages.addMessage( msg );
	    }
		else
		{
			ApexPages.Message msg = new ApexPages.Message( ApexPages.severity.FATAL, ' O texto da função de mensagem não foi informado! ' );
        	ApexPages.addMessage( msg );
		}	
	}

}