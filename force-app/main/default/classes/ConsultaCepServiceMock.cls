@isTest
global class ConsultaCepServiceMock 
{


	static testmethod void Test_MethodOne()
	{
	   //exemplo 

	   Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

	   
	}

	global class MockHttpResponseGenerator implements HttpCalloutMock 
	{
        String reponse;
			
		global HTTPResponse respond(HTTPRequest req) 
		{                    
			// Create a fake response
			HttpResponse res = new HttpResponse();
			res.setHeader('Content-Type', 'application/json');
			res.setBody( gerarResponse() );
			res.setStatusCode(200);
			return res;
		}
		
		public String gerarResponse()
		{
			reponse = '';
			
            reponse +=' {';
            reponse +='  "cep": "01001-000",';
            reponse +='  "logradouro": "Praça da Sé",';
            reponse +='  "complemento": "lado ímpar",';
            reponse +='  "bairro": "Sé",';
            reponse +='  "localidade": "São Paulo",';
            reponse +='  "uf": "SP",';
            reponse +='  "unidade": "",';
            reponse +='  "ibge": "3550308",';
            reponse +='  "gia": "1004"';
            reponse +=' }';
		
			return reponse;
		}
	}
	
	

}