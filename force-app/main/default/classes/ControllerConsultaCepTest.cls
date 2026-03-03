/*********************************************************************************************************************************************************************

@description Classe de comunicação do salesforce com o webservice desejado
@author Avanxo - Rodrigo Donha
@date 10/06/2019
		
**********************************************************************************************************************************************************************/
@isTest
public class ControllerConsultaCepTest 
{
    /** 
    @description  método para realizar o teste da controller de consulta de CEP
    @param String endpoint, String metodo
    @return String
    @author Rodrigo Donha
    @date 10/06/2019
	*/	
	static testmethod void buscarCEP()
    {
        Test.setMock(HttpCalloutMock.class, new ConsultaCepServiceMock.MockHttpResponseGenerator());
     
        
        PageReference  pagina = Page.ConsultaCEP;
        
        Test.setCurrentPageReference( pagina );
        
        ControllerConsultaCep controller = new ControllerConsultaCep();
        
        controller.cepBusca = '01317000';
        
        controller.buscarCEP();
        
    }
    
}