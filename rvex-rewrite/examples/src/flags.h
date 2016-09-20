#ifndef __FLAGS_H__
#define __FLAGS_H__

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "lmip_error.h"

/*---------------------------------------------------------------------------*/

/* enumeration for better readability */
enum flag_type{
  DOUBLE,
  INTEGER,
  STRING
};

/*---------------------------------------------------------------------------*/

/* flag data structure */
struct flag
{
  /* identifier of the flag */
  char* name;
  /* type of the arguments to the flag */
  enum flag_type type;
  /* argument list for the flag,
   * ATTENTION: in the case of a variable length list this must be a
   * pointer to such a list, because the algorithm must adjust the
   * size of the list
   */
  void* args;
  /* flag indicating if the flag was already processed */
  char read;
  /* flag indicating if the flag is required */
  char required;
  /* amount of required arguments for the flag,
   * special value -1 indicates that the flag accepts
   * a variable amount > 0 of arguments
   */
  int required_amount;
  /* storage location where the read amount is recorded,
   * this can be NULL, in this case no information is
   * recorded
   */
  int *amount;
};

/*---------------------------------------------------------------------------*/

/* flag list data structure */
struct flag_list
{
  /* current flag entry */
  struct flag* flag;
  /* pointer to next list entry */
  struct flag_list* next;
};

/*---------------------------------------------------------------------------*/

/* given a name find the corresponding flag structure */
struct flag* flags_find(
    /* INPUT */
    struct flag_list *flags, /* flag list to search */
    const char* name /* name of the flag */
    /* OUTPUT */
    /* return value */
    )
{
  /* current flag list entry, initialise it to flags */
  struct flag_list *current = flags;

  /* search the list */
  while ( current->next != NULL )
  {
    /* check if we found the correct flag */
    if( !strcmp( name, current->flag->name ))
    {
      /* yes, return the pointer to the flag */
      return current->flag;
    } /* end if */

    /* continue with next entry */
    current = current->next;
  } /* end while */

  /* we found no entry, return a NULL pointer */
  return NULL;

} /* end search_flag */
/*---------------------------------------------------------------------------*/

/* initialise the data structure */
void flags_create(
    /* INPUT */
    struct flag_list **flags
    )
{
  /* initialise storage for flag list */
  *flags = ( struct flag_list*) malloc ( sizeof ( struct flag_list ));

  /* mark end of list */
  (*flags)->next = NULL;

  /* return */
  return;
} /* end flags_create */

/*---------------------------------------------------------------------------*/

/* frees storage of the data structures */
void flags_destroy(
    /* INPUT */
    struct flag_list *flags /* flag list to destroy */
    )
{
  /* current flag list entry, initialise it to flags */
  struct flag_list *current = flags;

  /* verify that framework was initialised */
  if( current == NULL )
  {
    lmip_error( "error: flag framework not initialised.");
  } /* end if */
  
  /* free storage of list entries */
  while ( current->next != NULL )
  {
    /* save pointer to next entry */
    struct flag_list *help = current->next;
    /* free storage of name string */
    free( current->flag->name);
    /* free storage of flag */
    free( current->flag);
    /* free current list entry */
    free( current );
    /* proceed with next entry */
    current = help;
  } /* end while */

  /* free last entry */
  free( current );

  /* return */
  return;

} /* end flags_destroy */

/*---------------------------------------------------------------------------*/

/* prints usage information of the program by outputting the flag names */
void flags_print_usage(
    /* INPUT */
    struct flag_list *flags,
    const char* program_name
    )
{
  /* pointer to the current flag list entry, initialise it to flags */
  struct flag_list *current = flags;

  /* length of the current line */
  int len = 0;

  /* print a starting message */
  printf("\nusage:\n\n%s ", program_name);

  /* we wrote the program name + 1 space, increase len */
  len += strlen( program_name) + 1;

  /* process list */
  while ( current->next != NULL )
  {
    /* current flag */
    const struct flag* flag = current->flag;

    /* string representing the current type */
    char* type_string = 0;

    /* test if the flag is required */
    if( flag->required == 0)
    {
      /* the flag is not required -> print a [ + 1 space */
      printf("[ ");
      /* increase length by 2 */
      len += 2;
    }

    /* now print the flag name + 1 space */
    printf("%s ", flag->name);
    /* increase length */
    len += strlen(flag->name) + 1;

    /* depending on the type choose a different 
     * type string
     */
    switch(flag->type)
    {
      case INTEGER:
        type_string = "INTEGER";
        break;
      case DOUBLE:
        type_string = "DOUBLE";
        break;
      case STRING:
        type_string = "STRING";
        break;
    } /* end switch */

    /* check if this is variable length argument list */
    if( flag->required_amount == -1 )
    {
      /* this is a variable length list -> append LIST to
       * the type string
       */
      printf("%s LIST ", type_string);
      /* increase length */
      len += strlen( type_string) + 6;
    } /* end if */
    else
    {
      /* this is not a variable length list ->
       * print for each required argument the type string and 1 space
       */
      for( int i = 0; i < flag->required_amount; ++i)
      {
        printf("%s ", type_string);
        /* increase length */
        len += strlen( type_string ) + 1;
      } /* end for i */
    } /* end else */

    /* test if the flag is required */
    if( flag->required == 0)
    {
      /* the flag is not required -> print a ] + 1 space */
      printf("] ");
      /* increase length by 2 */
      len += 2;
    } /* end if */

    /* check if the current line length exceeds 60 */
    if( len >= 60 )
    {
      /* yes, end the line */
      printf("\n");

      /* reset the length to length of the program name + 1 space */
      len = strlen( program_name ) + 1;

      /* print len spaces */
      for( int j = 0; j < len; ++j) 
      {
        printf(" ");
      } /* end for */
    } /* end if */

    /* continue with next entry */
    current = current->next;
  } /* end while */

  /* print two newlines */
  printf("\n\n");

  /* return */
  return;
} /* end flags_print_usage */

/*---------------------------------------------------------------------------*/

/* verifies if all flags that are marked as required were processed */
int flags_all_read(
    /* INPUT */
    struct flag_list *flags /* flag list to check */
    )
{
  /* pointer to the current flag list entry, initialise it to flags */
  struct flag_list *current = flags;

  /* free storage of list entries */
  while ( current->next != NULL )
  {
    /* current flag */
    const struct flag* flag = current->flag;

    /* check if this is a required flag and if it was read */
    if( flag->read == 0 && flag->required != 0 )
    {
      /* the flag is required but was not read -> issue error */
      printf("\nerror: required flag %s not read.\n", flag->name);

      /* return 0 -> not all required flags were read */
      return 0;
    } /* end if */

    /* continue with next list entry */
    current = current->next;
  } /* end while */

  /* return 1 -> all flags were read */
  return 1;
} /* end flags_all_read */

/*---------------------------------------------------------------------------*/

/* adds a new flag specification */
void flags_add(
    /* INPUT */
    struct flag_list *flags, /* flag list to append the data to */
    const char* name, /* name of the flag */
    const enum flag_type type, /* type of the arguments belonging to the flag */
    const char required, /* flag indicating if the flag is required */
    const int required_amount, /* amount of required arguments belonging
                                  to the flag */
    void *args, /* storage location of the argument list */
    int *amount /* optional storage location where to write the amount of
                   read arguments to
                   */
    )
{
  /* length of the name string including the prefix -- and the terminating \0 
   * character
   */
  const int name_length = strlen( name ) + 3;
  struct flag_list *current = flags;

  /* allocate storage for string containing the prefixed name */
  char *prefixed_name = ( char* ) malloc( name_length  * sizeof(char));

  /* generate prefixed name */
  sprintf(prefixed_name, "%s%s", "--", name);

  /* verify that framework was initialised */
  if( current == NULL )
  {
    lmip_error( "flag framework not initialised.");

  } /* end if */
  
  /* search the end of the list */
  while ( current->next != NULL )
  {
    /* verify that we do not use a duplicate name */
    if( !strcmp( prefixed_name, current->flag->name ))
    {
      lmip_error( "error: duplicate entry.");
    } /* end if */

    /* continue with next entry */
    current = current->next;
  } /* end while */

  /* allocate storage for new flag entry and initialise entries */
  current->flag = (struct flag*) malloc( sizeof( struct flag ));

  /* set pointer to argument list storage */
  current->flag->args = args;
  current->flag->amount = amount;
  current->flag->required_amount = required_amount;

  /* set read flag to 0 */
  current->flag->read = 0;

  /* set name */
  current->flag->name = prefixed_name;

  /* set type of arguments */
  current->flag->type = type;
  /* set required flag */
  current->flag->required = required;

  /* now allocate storage for the next list entry */
  current->next = ( struct flag_list*) malloc( sizeof(struct flag_list) );

  /* mark the end of the list */
  current->next->next = NULL;

  /* return */
  return;
} /* end flags_add */

/*---------------------------------------------------------------------------*/

/* reallocates storage for a variable length argument list of a flag */
void flags_realloc_storage(
    /* INPUT */
    void* storage, /* pointer to storage */
    enum flag_type type, /* type of the arguments */
    int size /* new size of storage */
    )
{
  /* depending on the type we have to perform the reallocation slightly
   * differently
   */
  switch( type )
  {
    /* explanation of *( (TYPE ** ) storage ):
     * reinterpret the storage location as pointer to a TYPE array and
     * dereference this pointer to gain access to the array storage that
     * we want to modify
     * NOTE: the reinterpretation is necessary as C forbids dereferencing
     * a void pointer
     */
    case INTEGER:
      /* here we have TYPE = int */
      *( ( int ** ) storage ) = (int*)
        realloc( *( ( int ** ) storage ), size * sizeof(int) );
      break;
    case DOUBLE:
      /* here we have TYPE = double */
      *( ( double ** ) storage ) = (double*)
        realloc( *( ( double ** ) storage ), size * sizeof(double) );
      break;
    case STRING:
      /* here we have TYPE = char* */
      *( ( char *** ) storage ) = (char**)
        realloc( *( ( char *** ) storage ), size * sizeof(char*) );
      break;
  } /* end switch */

  /* return */
  return;

} /* end flags_realloc_storage */

/*---------------------------------------------------------------------------*/

/* read flags contained in a provided command line argument list */
void flags_read(
    struct flag_list *flags,
    const char* program_name,
    int argc,
    char* argv[]
    )
{
  /* verify that framework was initialised */
  if( flags == NULL )
  {
    lmip_error( "flag framework not initialised.");

  } /* end if */
 
  /* process the provided command line argument list */
  for( int i = 1; i < argc; )
  {
    /* pointer to the current flag being processed */
    struct flag *flag = NULL;

    /* amount of read arguments of the current flag */
    int amount = 0;

    /* try to find the flag belonging to the input */
    if( (flag = flags_find( flags, argv[i] )) == NULL )
    {
      /* the flag was not found -> issue error */
      printf( "error: unknown command line argument %s\n", argv[i] );
      flags_print_usage(flags, program_name );
      exit(1);
    } /* end if */

    /* check if we processed this flag earlier */
    if( flag->read != 0 )
    {
      /* the flag was already processed -> issue error */
      printf( "error: flag %s was already read \n", flag->name );
      flags_print_usage(flags, program_name );
      exit(1);
    } /* end if */

    /* now try to read the arguments for the current flag */
    while(
        /* verify that we are not done with the
         * entire command line arguments
         */
        ++i < argc &&
        /* and that the current string is not a flag itself */
        flags_find(flags, argv[i]) == NULL &&
        /* and that we are not finished reading the arguments
         * for the current flag
         * note: the variable length list does not have a fixed
         * amount of arguments
         */
        ( amount < flag->required_amount || 
          flag->required_amount == -1)
        )
    {
      /* increase amount of read arguments for the current flag */
      ++amount;

      /* if we have a variable length list we have to increase
       * the storage to hold the additional argument
       */
      if( flag->required_amount == -1)
      {
        /* increase storage */
        flags_realloc_storage( flag->args, flag->type, amount);
      } /* end if */
      
      /* storage pointers for each possible value type
         * in the argument list
         */
      int *entry_int = NULL;
      double *entry_double = NULL;
      char **entry_string = NULL;

      /* now decide how to read the values depending on the type of
       * the arguments belonging to the flag */
      switch( flag->type )
      {
        case INTEGER:
          /* get storage location for int value
           * ATTENTION: if we have a variable length list we
           * have to dereference the flag argument list first
           */
          entry_int = ( flag->required_amount == -1)?
            (int*) *( (int**) flag->args) : (int*) flag->args;

          /* try to read integer value */
          if( sscanf(argv[i], "%d", &( entry_int[amount-1] ) ) != 1 )
          {
            /* no integer could be read -> issue error */
            printf( "error: could not read INTEGER argument for flag %s \n",
                flag->name );
            flags_print_usage(flags, program_name );
            exit(1);
          } /* end if */
          break;

        case DOUBLE:
          /* get storage location for double value
           * ATTENTION: if we have a variable length list we
           * have to dereference the flag argument list first
           */
          entry_double = ( flag->required_amount == -1)?
            (double*) *( (double**) flag->args) : (double*) flag->args;

          /* try to read double value */
          if( sscanf(argv[i], "%lf", &( entry_double[amount-1]) ) != 1 )
          {
            /* no double could be read -> issue error */
            printf( "error: could not read DOUBLE argument for flag %s \n",
                flag->name );
            flags_print_usage(flags, program_name );
            exit(1);
          } /* end if */
          break;

        case STRING:
          /* get storage location for string value
           * ATTENTION: if we have a variable length list we
           * have to dereference the flag argument list first
           */
          entry_string = ( flag->required_amount == -1)?
            (char**) *( (char***) flag->args):(char**) flag->args;

          /* allocate storage for new string in argument list that is
           * large enough to hold the argument string and the terminating
           * \0 character
           */
          entry_string[amount-1] =
            (char*) malloc( sizeof( char ) * (strlen(argv[i]) + 1));

          /* verify that the current entry is not a flag name */
          if( flags_find( flags, argv[i] ) != NULL ) 
          {
            /* the string is a flag name -> issue error */
            printf( "error: could not read STRING argument for flag %s \n",
                flag->name );
            flags_print_usage(flags, program_name );
            exit(1);
          } /* end if */

          /* copy string to flag value */
          strcpy( entry_string[amount - 1], argv[i] );

          break;

        default:
          lmip_error("type unhandled.");
          break;

      } /* end switch */
    } /* end while */
    
    /* verify that we read the required amount of values
     * or at least 1 argument if this is a variable length
     * list
     */
    if( amount < 1 ||
        (amount < flag->required_amount &&
        flag->required_amount != -1))
    {
      printf( "error: wrong amount of arguments for flag %s \n",
          flag->name );
      flags_print_usage(flags, program_name );
      exit(1);
    } /* end if */

    /* mark flag as read */
    flag->read = 1;

    /* store amount of read arguments for current flag
     * if the framework was provided with a storage location
     */
    if( flag->amount != NULL )
    {
      *(flag->amount) = amount;
    } /* end if */

  } /* end for */

  /* verify that we read all required flags */
  if( !flags_all_read( flags ) )
  {
    flags_print_usage( flags, program_name );
    exit(1);
  } /* end if */

  return;
} /* end read_flags */
/*---------------------------------------------------------------------------*/
#endif
