@IsTest
public class MyIterableTest {
    // Test method to verify iteration using a for loop
    @IsTest
    static void testIterableForLoop() {
        // Create a list of strings
        List<String> strings = new List<String>{'Hello', 'World'};

        // Create an instance of MyIterable with the list of strings
        MyIterable iterable = new MyIterable(strings);

        // Use a for loop to iterate over the MyIterable instance and print each string
        for (String str : iterable) {
            System.debug(str);
        }
    }
}