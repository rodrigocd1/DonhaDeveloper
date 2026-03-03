public class AnimalLocator {
    public static String getAnimalNameById(Integer id)
    {
        String animalName;
        System.debug('ID is'+id);
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://th-apex-http-callout.herokuapp.com/animals/'+id);
        request.setMethod('GET');
        HttpResponse response = http.send(request);
        
        if (response.getStatusCode() == 200) {
            system.debug('===> response.getBody() ' + response.getBody());
            // Deserializes the JSON string into collections of primitive data types.
             Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
             Map<String, Object> animal = (Map<String, Object>) results.get('animal');
             animalName=(String)animal.get('name');

        }
        System.debug(''+animalName);
        return animalName;
    }

}