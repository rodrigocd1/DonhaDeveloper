public class ExemploJsonNaPratica {
    
    public static void RestNaPratica() {
        
        // Cria uma instância da classe Http
        Http http = new Http();
        
        // Cria uma requisição HTTP
        HttpRequest request = new HttpRequest();
        
        // Define o endpoint da requisição
        request.setEndpoint('https://th-apex-http-callout.herokuapp.com/animals');
        
        // Define o método HTTP como GET
        request.setMethod('GET');
        
        // Envia a requisição HTTP e recebe a resposta
        HttpResponse response = http.send(request);
        
        // Se a requisição for bem-sucedida (código de status 200), analisa a resposta JSON.
        
        if (response.getStatusCode() == 200) 
        {
            // Desserializa a string JSON em coleções de tipos de dados primitivos.
            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            
            // Converte os valores na chave 'animals' em uma lista
            List<Object> animals = (List<Object>) results.get('animals');
            
            // Registra os animais recebidos no log de depuração
            System.debug('Recebidos os seguintes animais:');
            
            for (Object animal : animals) 
            {
                System.debug(animal);
            }
        }
    }
}