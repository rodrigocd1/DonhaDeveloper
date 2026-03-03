@isTest
private class TestWrapperClass 
{

    static testMethod void testPageWrapperClass() 
    {
    	
    	PageReference pageRef = Page.WrapperClass;
    	 
    	Account conta = new Account();
    	conta.Name = 'teste';
    	conta.Type = 'teste';
    	conta.Website = 'www.teste.com.br';     	
    	conta.Price__c = 400;
    	insert conta;
    	
    	/** Chama o parametro da página VisualForce */
	    Test.setCurrentPageReference(pageRef);
	    
	    /** Chama e inicia o StandardController e o controller da página */
	    WrapperClass wc = new WrapperClass();	            
        
        Test.setCurrentPage(pageRef);
    	
    	AccountWrapper ac = new accountWrapper( conta );    	
    	
    	
    	
    	wc.carregarCriteriosDeFiltros();
    	wc.carregarListaCamposConta();
    	wc.pesquisar(); 
    	
    	wc.accountWrapperObject();
    	
    	wc.getselected();
    			
    	try{wc.Changetype();}catch(Exception e){}
    	try{wc.orderByName();}catch(Exception e){}    
    	try{wc.orderByType();}catch(Exception e){}
    	try{wc.orderByWebsite();}catch(Exception e){}	   	    	
    	
    	TestOzVisualForceMensagens.testExibirMensagemAviso();
    	TestOzVisualForceMensagens.testExibirMensagemErro();
    	TestOzVisualForceMensagens.testExibirMensagemErroFatal();
    	TestOzVisualForceMensagens.testExibirMensagemInformacao();
    	TestOzVisualForceMensagens.testExibirMensagemSucesso();
    	
        
    }
}