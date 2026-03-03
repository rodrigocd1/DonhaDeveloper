public class MyIterable implements Iterable<String> {
    // Private field to hold the list of strings
    private List<String> strings;

    // Constructor to initialize the strings field
    public MyIterable(List<String> strings) {
        this.strings = strings;
    }

    // Implement the iterator method
    public Iterator<String> iterator() {
        return strings.iterator();
    }
}