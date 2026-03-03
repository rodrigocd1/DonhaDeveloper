/**********************************************************************************************************************************************************************

 Desenvolvido por Avanxo Brasil

 Classe testada: OzVisualForceMensagens.

 Métodos testados: exibirMensagemInformacao, exibirMensagemErro, exibirMensagemErroFatal, exibirMensagemSucesso, exibirMensagemAviso.

**********************************************************************************************************************************************************************/

@isTest
public class TestOzVisualForceMensagens 
{
	
	/** Testa o método exibirMensagemInformacao */
	public static testMethod void testExibirMensagemInformacao()
	{
		try
		{
			OzVisualForceMensagens.exibirMensagemInformacao( null );
		}
		catch( Exception e )
		{
			
		}
		OzVisualForceMensagens.exibirMensagemInformacao( 'Mensagem de Informação' );
	}
	
	
	
	/** Testa o método exibirMensagemErro */
	public static testMethod void testExibirMensagemErro()
	{
		try
		{
			OzVisualForceMensagens.exibirMensagemErro( null );
		}
		catch( Exception e )
		{
			
		}
		OzVisualForceMensagens.exibirMensagemErro( 'Mensagem de Erro' );
	}
	
	
	
	/** Testa o método exibirMensagemErroFatal */
	public static testMethod void testExibirMensagemErroFatal()
	{
		try
		{
			OzVisualForceMensagens.exibirMensagemErroFatal( null );
		}
		catch( Exception e )
		{
			
		}
		OzVisualForceMensagens.exibirMensagemErroFatal( 'Mensagem de Erro Fatal' );
	}
	
	
	
	/** Testa o método exibirMensagemSucesso */
	public static testMethod void testExibirMensagemSucesso()
	{
		try
		{
			OzVisualForceMensagens.exibirMensagemSucesso( null );
		}
		catch( Exception e )
		{
			
		}
		OzVisualForceMensagens.exibirMensagemSucesso( 'Mensagem de Sucesso' );
	}
	
	
	
	/** Testa o método exibirMensagemAviso */
	public static testMethod void testExibirMensagemAviso()
	{
		try
		{
			OzVisualForceMensagens.exibirMensagemAviso( null );
		}
		catch( Exception e )
		{
			
		}
		OzVisualForceMensagens.exibirMensagemAviso( 'Mensagem de Aviso' );
	}
	
}